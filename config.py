"""
Configuration management for LLM Optimization Workspace.
Uses Pydantic Settings with environment variable support and hardware validation.
"""

import os
import platform
import psutil
from pathlib import Path
from typing import Dict, List, Optional, Union

from pydantic import BaseModel, Field, field_validator, model_validator
from pydantic_settings import BaseSettings


class HardwareConfig(BaseModel):
    """Hardware-specific configuration for Intel i5-9500 optimization."""
    
    cpu_cores: int = Field(default=6, description="Number of physical CPU cores")
    logical_processors: int = Field(default=6, description="Total logical processors")
    threads: int = Field(default=6, description="Optimal thread count for llama.cpp")
    cpu_affinity: str = Field(default="Maximum", description="CPU affinity setting")
    priority: str = Field(default="RealTime", description="Process priority")
    avx2_enabled: bool = Field(default=True, description="AVX2 instruction support")
    
    @field_validator('threads')
    @classmethod
    def validate_threads(cls, v, info):
        """Ensure thread count doesn't exceed physical cores for i5-9500."""
        cpu_cores = info.data.get('cpu_cores', 6)
        if v > cpu_cores:
            # i5-9500 has no hyperthreading, limit to physical cores
            return cpu_cores
        return v
    
    @field_validator('cpu_affinity')
    @classmethod
    def validate_cpu_affinity(cls, v):
        """Validate CPU affinity setting."""
        valid_affinities = ["Maximum", "High", "Normal", "Low"]
        if v not in valid_affinities:
            raise ValueError(f"CPU affinity must be one of: {valid_affinities}")
        return v
    
    @field_validator('priority')
    @classmethod
    def validate_priority(cls, v):
        """Validate process priority setting."""
        valid_priorities = ["RealTime", "High", "AboveNormal", "Normal", "BelowNormal", "Low"]
        if v not in valid_priorities:
            raise ValueError(f"Priority must be one of: {valid_priorities}")
        return v


class ModelPaths(BaseModel):
    """Model file paths configuration."""
    
    default: str = Field(default=".\\Tools\\models\\llama-3.2-1b-instruct-q4_k_m.gguf")
    tinyllama: str = Field(default=".\\Tools\\models\\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")
    phi2: str = Field(default=".\\Tools\\models\\phi-2.Q4_K_M.gguf")
    qwen: str = Field(default=".\\Tools\\models\\qwen2.5-1.5b-instruct-q4_k_m.gguf")
    gemma: str = Field(default=".\\Tools\\models\\gemma-3-4b-it-q4_k_m.gguf")
    
    # Extended model paths from the comprehensive collection
    qwen_coder: str = Field(default=".\\Tools\\models\\qwen2.5-coder-1.5b-instruct-q4_k_m.gguf")
    smolLM2: str = Field(default=".\\Tools\\models\\smolLM2-1.7b-instruct-q4_k_m.gguf")
    phi4_mini: str = Field(default=".\\Tools\\models\\phi-4-mini-instruct-q4_k_m.gguf")
    qwen3_4b: str = Field(default=".\\Tools\\models\\qwen3-4b-q4_k_m.gguf")
    smollm3: str = Field(default=".\\Tools\\models\\smollm3-3b-q4_k_m.gguf")
    deepseek_r1: str = Field(default=".\\Tools\\models\\deepseek-r1-distill-qwen-14b-q4_k_m.gguf")
    
    @field_validator('*')
    @classmethod
    def validate_model_exists(cls, v, info):
        """Validate that model files exist."""
        field_name = info.field_name
        if field_name != '__root__':  # Skip root validator
            model_path = Path(v)
            if not model_path.exists():
                raise ValueError(f"Model file not found: {v}")
        return v


class BinaryPaths(BaseModel):
    """llama.cpp binary paths configuration."""
    
    main: str = Field(default=".\\Tools\\bin\\main.exe")
    server: str = Field(default=".\\Tools\\bin\\llama-server.exe")
    quantize: str = Field(default=".\\Tools\\bin\\llama-quantize.exe")
    avx2: str = Field(default=".\\Tools\\bin\\main.exe")  # AVX2 optimized version


class OptimizationDefaults(BaseModel):
    """Default optimization parameters for llama.cpp."""
    
    threads: int = Field(default=6, description="Number of threads to use")
    context_size: int = Field(default=2048, description="Context window size")
    batch_size: int = Field(default=512, description="Batch size for processing")
    micro_batch_size: int = Field(default=32, description="Micro batch size")
    gpu_layers: int = Field(default=0, description="Number of GPU layers (0 for CPU-only)")
    kv_cache_type: str = Field(default="q8_0", description="KV cache quantization type")
    
    @field_validator('threads')
    @classmethod
    def validate_threads(cls, v):
        """Ensure reasonable thread limits."""
        if v < 1 or v > 32:
            raise ValueError("Threads must be between 1 and 32")
        return v
    
    @field_validator('context_size')
    @classmethod
    def validate_context_size(cls, v):
        """Ensure reasonable context size."""
        if v < 512 or v > 32768:
            raise ValueError("Context size must be between 512 and 32768")
        return v
    
    @field_validator('kv_cache_type')
    @classmethod
    def validate_kv_cache_type(cls, v):
        """Validate KV cache quantization type."""
        valid_types = ["f16", "q8_0", "q4_0", "q4_1"]
        if v not in valid_types:
            raise ValueError(f"KV cache type must be one of: {valid_types}")
        return v


class ServerConfig(BaseModel):
    """FastAPI server configuration."""
    
    host: str = Field(default="127.0.0.1", description="Server host")
    port: int = Field(default=8000, description="Server port")
    debug: bool = Field(default=False, description="Debug mode")
    reload: bool = Field(default=False, description="Auto-reload on code changes")
    log_level: str = Field(default="INFO", description="Logging level")
    
    @field_validator('port')
    @classmethod
    def validate_port(cls, v):
        """Validate port range."""
        if v < 1 or v > 65535:
            raise ValueError("Port must be between 1 and 65535")
        return v
    
    @field_validator('log_level')
    @classmethod
    def validate_log_level(cls, v):
        """Validate log level."""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v not in valid_levels:
            raise ValueError(f"Log level must be one of: {valid_levels}")
        return v


class DatabaseConfig(BaseModel):
    """Database configuration for ChromaDB and SQLite."""
    
    chroma_persist_directory: str = Field(default="./chroma_db", description="ChromaDB storage directory")
    sqlite_database_url: str = Field(default="sqlite:///./llm_server.db", description="SQLite connection string")
    
    @field_validator('chroma_persist_directory')
    @classmethod
    def validate_chroma_directory(cls, v):
        """Ensure ChromaDB directory path is valid."""
        path = Path(v)
        # Create directory if it doesn't exist
        path.mkdir(parents=True, exist_ok=True)
        return str(path.absolute())


class SecurityConfig(BaseModel):
    """Security configuration."""
    
    api_key: str = Field(default="dev-key-change-in-production", description="API key for authentication")
    api_key_header: str = Field(default="X-API-Key", description="API key header name")
    enable_auth: bool = Field(default=True, description="Enable authentication")
    allowed_origins: List[str] = Field(default=["http://localhost:3000", "http://localhost:8000"], description="CORS allowed origins")


class Settings(BaseSettings):
    """Main application settings with environment variable support."""
    
    # Model configurations
    model_paths: ModelPaths = Field(default_factory=ModelPaths)
    binary_paths: BinaryPaths = Field(default_factory=BinaryPaths)
    hardware_config: HardwareConfig = Field(default_factory=HardwareConfig)
    optimization_defaults: OptimizationDefaults = Field(default_factory=OptimizationDefaults)
    
    # Server configuration
    server: ServerConfig = Field(default_factory=ServerConfig)
    database: DatabaseConfig = Field(default_factory=DatabaseConfig)
    security: SecurityConfig = Field(default_factory=SecurityConfig)
    
    # Environment-specific settings
    environment: str = Field(default="development", description="Environment (development/production)")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        env_nested_delimiter = "__"
        case_sensitive = False
    
    @field_validator('environment')
    @classmethod
    def validate_environment(cls, v):
        """Validate environment setting."""
        valid_envs = ["development", "production", "testing"]
        if v not in valid_envs:
            raise ValueError(f"Environment must be one of: {valid_envs}")
        return v.lower()
    
    @model_validator(mode='after')
    def validate_hardware_compatibility(cls, model):
        """Validate hardware compatibility and optimize settings."""
        hardware_config = model.hardware_config
        optimization_defaults = model.optimization_defaults
        
        if hardware_config and optimization_defaults:
            # Ensure thread count matches hardware
            optimization_defaults.threads = min(
                optimization_defaults.threads, 
                hardware_config.cpu_cores
            )
            
            # Disable GPU layers if not available (CPU-only setup)
            if optimization_defaults.gpu_layers > 0:
                import warnings
                warnings.warn("GPU layers detected but this is a CPU-only setup. Setting gpu_layers to 0.")
                optimization_defaults.gpu_layers = 0
        
        return model
    
    def get_model_info(self, model_name: str) -> Optional[Dict[str, str]]:
        """Get model information by name."""
        model_paths = self.model_paths.dict()
        if model_name in model_paths:
            path = model_paths[model_name]
            model_file = Path(path)
            if model_file.exists():
                return {
                    "name": model_name,
                    "path": str(model_file.absolute()),
                    "size": model_file.stat().st_size,
                    "exists": True
                }
        return None
    
    def get_available_models(self) -> List[str]:
        """Get list of available models."""
        available = []
        for name, path in self.model_paths.dict().items():
            if Path(path).exists():
                available.append(name)
        return available
    
    def is_production(self) -> bool:
        """Check if running in production mode."""
        return self.environment == "production"
    
    def get_llamacpp_command_args(self, model_name: str = None) -> List[str]:
        """Generate llama.cpp command line arguments."""
        args = []
        
        # Model path
        if model_name:
            model_info = self.get_model_info(model_name)
            if model_info:
                args.extend(["-m", model_info["path"]])
        
        # Hardware optimization
        args.extend(["-t", str(self.optimization_defaults.threads)])
        args.extend(["-c", str(self.optimization_defaults.context_size)])
        args.extend(["-b", str(self.optimization_defaults.batch_size)])
        args.extend(["--ctx-size", str(self.optimization_defaults.context_size)])
        
        # KV cache quantization
        if self.optimization_defaults.kv_cache_type:
            args.extend(["--kv-cache-type", self.optimization_defaults.kv_cache_type])
        
        # GPU layers (should be 0 for CPU-only)
        if self.optimization_defaults.gpu_layers > 0:
            args.extend(["-ngl", str(self.optimization_defaults.gpu_layers)])
        
        return args


def get_settings() -> Settings:
    """Get application settings instance."""
    return Settings()


def validate_system_requirements() -> Dict[str, Union[bool, str]]:
    """Validate system requirements for the LLM server."""
    requirements = {
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "cpu_count": psutil.cpu_count(logical=False),
        "memory_gb": round(psutil.virtual_memory().total / (1024**3), 1),
        "disk_free_gb": round(psutil.disk_usage('.').free / (1024**3), 1),
    }
    
    # Check minimum requirements
    warnings = []
    
    # Python version
    if tuple(map(int, platform.python_version().split('.'))) < (3, 8):
        warnings.append("Python 3.8+ required")
    
    # Memory
    if requirements["memory_gb"] < 8:
        warnings.append("Less than 8GB RAM may cause performance issues")
    
    # Disk space
    if requirements["disk_free_gb"] < 10:
        warnings.append("Less than 10GB free disk space")
    
    requirements["warnings"] = warnings
    requirements["valid"] = len(warnings) == 0
    
    return requirements


# Global settings instance
settings = get_settings()
