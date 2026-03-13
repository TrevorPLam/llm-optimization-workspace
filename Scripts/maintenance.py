"""
ChromaDB maintenance script wrapper for T-006.4.

This script provides a Python interface to chromadb-ops CLI operations
including database info, WAL maintenance, and backup functionality.
"""

import asyncio
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, Any, Optional, List
import structlog


logger = structlog.get_logger(__name__)


class ChromaMaintenanceManager:
    """ChromaDB maintenance operations manager."""
    
    def __init__(self, db_path: str = "chroma_db"):
        self.db_path = Path(db_path)
        self.chromadb_ops_available = self._check_chromadb_ops()
        
    def _check_chromadb_ops(self) -> bool:
        """Check if chromadb-ops CLI is available."""
        try:
            result = subprocess.run(
                ["chops", "--version"], 
                capture_output=True, 
                text=True, 
                timeout=10
            )
            if result.returncode == 0:
                logger.info("chromadb-ops CLI available", version=result.stdout.strip())
                return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        logger.warning("chromadb-ops CLI not found, maintenance operations limited")
        return False
    
    async def get_database_info(self, privacy_mode: bool = False) -> Dict[str, Any]:
        """Get comprehensive database information using chromadb-ops."""
        if not self.chromadb_ops_available:
            return {
                "error": "chromadb-ops CLI not available",
                "fallback_info": await self._get_fallback_info()
            }
        
        try:
            cmd = ["chops", "db", "info", str(self.db_path)]
            if privacy_mode:
                cmd.append("-p")
            
            result = await asyncio.to_thread(
                subprocess.run, 
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=30
            )
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "raw_output": result.stdout,
                    "parsed_info": self._parse_db_info(result.stdout)
                }
            else:
                return {
                    "success": False,
                    "error": result.stderr,
                    "command": " ".join(cmd)
                }
                
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "Database info command timed out"
            }
        except Exception as e:
            logger.error("Failed to get database info", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }
    
    async def commit_wal(self, skip_collections: Optional[List[str]] = None, 
                        force: bool = False) -> Dict[str, Any]:
        """Commit WAL entries to HNSW index."""
        if not self.chromadb_ops_available:
            return {
                "success": False,
                "error": "chromadb-ops CLI not available for WAL operations"
            }
        
        try:
            cmd = ["chops", "wal", "commit", str(self.db_path)]
            
            if skip_collections:
                for collection in skip_collections:
                    cmd.extend(["--skip", collection])
            
            if force:
                cmd.append("-y")
            
            result = await asyncio.to_thread(
                subprocess.run, 
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=60
            )
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "output": result.stdout,
                    "wal_committed": True
                }
            else:
                return {
                    "success": False,
                    "error": result.stderr,
                    "command": " ".join(cmd)
                }
                
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "WAL commit command timed out"
            }
        except Exception as e:
            logger.error("Failed to commit WAL", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }
    
    async def clean_wal(self, force: bool = False) -> Dict[str, Any]:
        """Clean up committed WAL entries and VACUUM database."""
        if not self.chromadb_ops_available:
            return {
                "success": False,
                "error": "chromadb-ops CLI not available for WAL operations"
            }
        
        try:
            cmd = ["chops", "wal", "clean", str(self.db_path)]
            if force:
                cmd.append("-y")
            
            result = await asyncio.to_thread(
                subprocess.run, 
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=60
            )
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "output": result.stdout,
                    "wal_cleaned": True
                }
            else:
                return {
                    "success": False,
                    "error": result.stderr,
                    "command": " ".join(cmd)
                }
                
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "WAL clean command timed out"
            }
        except Exception as e:
            logger.error("Failed to clean WAL", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }
    
    async def create_snapshot(self, collection_name: str, 
                            output_path: str, force: bool = False) -> Dict[str, Any]:
        """Create a collection snapshot."""
        if not self.chromadb_ops_available:
            return {
                "success": False,
                "error": "chromadb-ops CLI not available for snapshot operations"
            }
        
        try:
            output_path = Path(output_path)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            
            cmd = [
                "chops", "collection", "snapshot", 
                str(self.db_path), 
                "--collection", collection_name,
                "--output", str(output_path)
            ]
            if force:
                cmd.append("-y")
            
            result = await asyncio.to_thread(
                subprocess.run, 
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=120
            )
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "output": result.stdout,
                    "snapshot_path": str(output_path),
                    "file_size": output_path.stat().st_size if output_path.exists() else 0
                }
            else:
                return {
                    "success": False,
                    "error": result.stderr,
                    "command": " ".join(cmd)
                }
                
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "Snapshot creation timed out"
            }
        except Exception as e:
            logger.error("Failed to create snapshot", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }
    
    async def get_wal_info(self) -> Dict[str, Any]:
        """Get WAL information."""
        if not self.chromadb_ops_available:
            return {
                "success": False,
                "error": "chromadb-ops CLI not available for WAL operations"
            }
        
        try:
            cmd = ["chops", "wal", "info", str(self.db_path)]
            
            result = await asyncio.to_thread(
                subprocess.run, 
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=30
            )
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "output": result.stdout,
                    "wal_info": self._parse_wal_info(result.stdout)
                }
            else:
                return {
                    "success": False,
                    "error": result.stderr,
                    "command": " ".join(cmd)
                }
                
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "WAL info command timed out"
            }
        except Exception as e:
            logger.error("Failed to get WAL info", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }
    
    async def run_maintenance_suite(self, backup_path: Optional[str] = None) -> Dict[str, Any]:
        """Run complete maintenance suite: info -> commit -> clean -> backup."""
        results = {
            "maintenance_suite": True,
            "start_time": asyncio.get_event_loop().time(),
            "operations": {}
        }
        
        try:
            # 1. Get database info
            logger.info("Starting maintenance suite", step="database_info")
            info_result = await self.get_database_info(privacy_mode=True)
            results["operations"]["database_info"] = info_result
            
            # 2. Commit WAL
            logger.info("Maintenance suite", step="wal_commit")
            commit_result = await self.commit_wal(force=True)
            results["operations"]["wal_commit"] = commit_result
            
            # 3. Clean WAL
            logger.info("Maintenance suite", step="wal_clean")
            clean_result = await self.clean_wal(force=True)
            results["operations"]["wal_clean"] = clean_result
            
            # 4. Create backup if requested
            if backup_path:
                logger.info("Maintenance suite", step="backup", backup_path=backup_path)
                backup_result = await self.create_backup(backup_path)
                results["operations"]["backup"] = backup_result
            
            results["end_time"] = asyncio.get_event_loop().time()
            results["duration"] = results["end_time"] - results["start_time"]
            results["success"] = all(
                op.get("success", False) for op in results["operations"].values()
            )
            
            logger.info("Maintenance suite completed", 
                       success=results["success"],
                       duration=results["duration"])
            
            return results
            
        except Exception as e:
            logger.error("Maintenance suite failed", error=str(e))
            results["error"] = str(e)
            results["success"] = False
            return results
    
    async def create_backup(self, backup_path: str) -> Dict[str, Any]:
        """Create a comprehensive backup of the database."""
        try:
            backup_path = Path(backup_path)
            backup_path.mkdir(parents=True, exist_ok=True)
            
            # Simple file-based backup for now
            # In production, you'd use collection snapshots
            import shutil
            
            timestamp = asyncio.get_event_loop().time()
            backup_dir = backup_path / f"chroma_backup_{int(timestamp)}"
            
            if self.db_path.exists():
                shutil.copytree(self.db_path, backup_dir, dirs_exist_ok=True)
                
                return {
                    "success": True,
                    "backup_path": str(backup_dir),
                    "backup_type": "file_copy",
                    "timestamp": timestamp
                }
            else:
                return {
                    "success": False,
                    "error": "Database path does not exist"
                }
                
        except Exception as e:
            logger.error("Failed to create backup", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }
    
    def _parse_db_info(self, output: str) -> Dict[str, Any]:
        """Parse database info output into structured data."""
        # Simple parsing - in production you'd want more sophisticated parsing
        lines = output.split('\n')
        parsed = {}
        
        for line in lines:
            if 'Chroma Version' in line:
                parsed['version'] = line.split(':')[1].strip() if ':' in line else 'unknown'
            elif 'Persist Directory Size' in line:
                parsed['size'] = line.split(':')[1].strip() if ':' in line else 'unknown'
        
        return parsed
    
    def _parse_wal_info(self, output: str) -> Dict[str, Any]:
        """Parse WAL info output into structured data."""
        lines = output.split('\n')
        parsed = {'collections': []}
        
        for line in lines:
            if '│' in line and not line.startswith('┃'):
                parts = line.split('│')
                if len(parts) >= 3:
                    collection = parts[1].strip()
                    count = parts[2].strip()
                    if collection and count.isdigit():
                        parsed['collections'].append({
                            'collection': collection,
                            'wal_entries': int(count)
                        })
        
        return parsed
    
    async def _get_fallback_info(self) -> Dict[str, Any]:
        """Get basic database info without chromadb-ops."""
        try:
            if not self.db_path.exists():
                return {"error": "Database path does not exist"}
            
            # Calculate directory size
            total_size = 0
            file_count = 0
            
            for file_path in self.db_path.rglob("*"):
                if file_path.is_file():
                    total_size += file_path.stat().st_size
                    file_count += 1
            
            return {
                "path": str(self.db_path),
                "size_bytes": total_size,
                "size_mb": round(total_size / (1024 * 1024), 2),
                "file_count": file_count,
                "exists": True
            }
            
        except Exception as e:
            return {"error": str(e)}


# CLI interface for standalone execution
async def main():
    """CLI interface for maintenance operations."""
    import argparse
    
    parser = argparse.ArgumentParser(description="ChromaDB Maintenance Tool")
    parser.add_argument("--db-path", default="chroma_db", help="ChromaDB database path")
    parser.add_argument("--operation", choices=[
        "info", "wal-commit", "wal-clean", "wal-info", "snapshot", "backup", "maintenance-suite"
    ], required=True, help="Maintenance operation to perform")
    parser.add_argument("--collection", help="Collection name for snapshot")
    parser.add_argument("--output", help="Output path for snapshot/backup")
    parser.add_argument("--force", action="store_true", help="Force operation without confirmation")
    parser.add_argument("--privacy", action="store_true", help="Privacy mode for info")
    
    args = parser.parse_args()
    
    manager = ChromaMaintenanceManager(args.db_path)
    
    if args.operation == "info":
        result = await manager.get_database_info(privacy_mode=args.privacy)
    elif args.operation == "wal-commit":
        result = await manager.commit_wal(force=args.force)
    elif args.operation == "wal-clean":
        result = await manager.clean_wal(force=args.force)
    elif args.operation == "wal-info":
        result = await manager.get_wal_info()
    elif args.operation == "snapshot":
        if not args.collection or not args.output:
            print("Error: --collection and --output required for snapshot")
            sys.exit(1)
        result = await manager.create_snapshot(args.collection, args.output, args.force)
    elif args.operation == "backup":
        if not args.output:
            print("Error: --output required for backup")
            sys.exit(1)
        result = await manager.create_backup(args.output)
    elif args.operation == "maintenance-suite":
        result = await manager.run_maintenance_suite(args.output)
    
    print(json.dumps(result, indent=2))
    sys.exit(0 if result.get("success", False) else 1)


if __name__ == "__main__":
    asyncio.run(main())
