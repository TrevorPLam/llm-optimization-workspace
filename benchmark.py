#!/usr/bin/env python3
"""
llama.cpp Model Performance Benchmark Script
Equivalent to Ollama benchmarking for T-002 requirements
Tests token generation speed and model performance on i5-9500
"""

import json
import time
import subprocess
import os
import sys
from pathlib import Path
from datetime import datetime

class ModelBenchmark:
    def __init__(self):
        self.workspace_dir = Path(__file__).parent
        self.config_file = self.workspace_dir / "llamacpp_config.json"
        self.results = []
        
    def load_config(self):
        """Load hardware configuration"""
        with open(self.config_file, 'r') as f:
            return json.load(f)
    
    def run_model_test(self, model_path, prompt, max_tokens=50):
        """Run inference test with a specific model"""
        config = self.load_config()
        opt = config["model_deployment"]["optimization_settings"]
        
        # Build llama.cpp command
        cmd = [
            str(self.workspace_dir / "Tools" / "bin" / "main.exe"),
            "-m", str(model_path),
            "-p", prompt,
            "-n", str(max_tokens),
            "--temp", str(opt["temperature"]),
            "-t", str(opt["threads"]),
            "-c", str(opt["context_size"]),
            "--batch-size", str(opt["batch_size"]),
            "--ctx-size", str(opt["context_size"]),
            "--log-disable"
        ]
        
        try:
            start_time = time.time()
            result = subprocess.run(
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=60,
                cwd=str(self.workspace_dir / "Tools" / "bin")
            )
            end_time = time.time()
            
            if result.returncode == 0:
                # Count generated tokens (rough estimate)
                output_text = result.stdout.strip()
                token_count = len(output_text.split())
                
                # Calculate metrics
                duration = end_time - start_time
                tokens_per_second = token_count / duration if duration > 0 else 0
                
                return {
                    "success": True,
                    "duration": duration,
                    "tokens_generated": token_count,
                    "tokens_per_second": tokens_per_second,
                    "output": output_text
                }
            else:
                return {
                    "success": False,
                    "error": result.stderr,
                    "return_code": result.returncode
                }
                
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "Timeout after 60 seconds"
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }
    
    def benchmark_all_models(self):
        """Benchmark all configured models"""
        config = self.load_config()
        models = config["model_deployment"]["model_paths"]
        
        test_prompts = [
            "Hello, how are you?",
            "What is 2+2?",
            "Explain machine learning briefly.",
            "Write a Python function to add two numbers."
        ]
        
        print("Starting llama.cpp Model Benchmark")
        print("=" * 50)
        print(f"Hardware: Intel i5-9500, 6 cores, {config['model_deployment']['hardware_config']['memory_bandwidth']}")
        print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        for model_name, model_path in models.items():
            if not Path(model_path).exists():
                print(f"❌ Model not found: {model_path}")
                continue
                
            print(f"🧪 Testing {model_name}")
            print(f"   Model: {Path(model_path).name}")
            
            model_results = []
            for i, prompt in enumerate(test_prompts[:2]):  # Test 2 prompts per model
                print(f"   Prompt {i+1}: {prompt[:30]}...")
                
                result = self.run_model_test(model_path, prompt, max_tokens=30)
                
                if result["success"]:
                    tps = result["tokens_per_second"]
                    print(f"   ✅ {tps:.1f} tokens/sec")
                    model_results.append(result)
                else:
                    print(f"   ❌ Error: {result.get('error', 'Unknown error')}")
                    model_results.append(result)
            
            # Calculate average for this model
            successful_results = [r for r in model_results if r["success"]]
            if successful_results:
                avg_tps = sum(r["tokens_per_second"] for r in successful_results) / len(successful_results)
                self.results.append({
                    "model": model_name,
                    "model_path": model_path,
                    "average_tps": avg_tps,
                    "tests": successful_results
                })
                print(f"   📊 Average: {avg_tps:.1f} tokens/sec")
            print()
    
    def generate_report(self):
        """Generate benchmark report"""
        config = self.load_config()
        targets = config["model_deployment"]["performance_targets"]
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "hardware": config["model_deployment"]["hardware_config"],
            "targets": targets,
            "results": self.results,
            "summary": {
                "models_tested": len(self.results),
                "fastest_model": None,
                "slowest_model": None,
                "meets_targets": []
            }
        }
        
        if self.results:
            fastest = max(self.results, key=lambda x: x["average_tps"])
            slowest = min(self.results, key=lambda x: x["average_tps"])
            
            report["summary"]["fastest_model"] = {
                "name": fastest["model"],
                "tps": fastest["average_tps"]
            }
            report["summary"]["slowest_model"] = {
                "name": slowest["model"], 
                "tps": slowest["average_tps"]
            }
            
            # Check if targets are met
            for result in self.results:
                model_size = self.get_model_size_category(result["model"])
                target_key = f"tokens_per_second_{model_size}"
                if target_key in targets:
                    target = float(targets[target_key].split("-")[0])  # Get minimum target
                    meets_target = result["average_tps"] >= target
                    report["summary"]["meets_targets"].append({
                        "model": result["model"],
                        "target": target,
                        "actual": result["average_tps"],
                        "meets_target": meets_target
                    })
        
        # Save report
        report_file = self.workspace_dir / "benchmark_report.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"📄 Benchmark report saved to: {report_file}")
        return report
    
    def get_model_size_category(self, model_name):
        """Determine model size category from name"""
        if "1b" in model_name.lower() or "0.5b" in model_name.lower():
            return "1b"
        elif "3b" in model_name.lower():
            return "3b"
        elif "7b" in model_name.lower():
            return "7b"
        else:
            return "unknown"
    
    def print_summary(self, report):
        """Print benchmark summary"""
        print("\n" + "=" * 50)
        print("BENCHMARK SUMMARY")
        print("=" * 50)
        
        summary = report["summary"]
        print(f"Models tested: {summary['models_tested']}")
        
        if summary["fastest_model"]:
            print(f"Fastest: {summary['fastest_model']['name']} ({summary['fastest_model']['tps']:.1f} t/s)")
        
        if summary["slowest_model"]:
            print(f"Slowest: {summary['slowest_model']['name']} ({summary['slowest_model']['tps']:.1f} t/s)")
        
        print("\nTarget Performance:")
        for target_check in summary["meets_targets"]:
            status = "✅" if target_check["meets_target"] else "❌"
            print(f"{status} {target_check['model']}: {target_check['actual']:.1f} t/s (target: {target_check['target']} t/s)")

if __name__ == "__main__":
    benchmark = ModelBenchmark()
    
    try:
        benchmark.benchmark_all_models()
        report = benchmark.generate_report()
        benchmark.print_summary(report)
        
        print("\n🎉 Benchmark completed!")
        
    except KeyboardInterrupt:
        print("\n⚠️ Benchmark interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Benchmark failed: {e}")
        sys.exit(1)
