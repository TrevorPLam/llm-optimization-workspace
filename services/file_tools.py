"""
Secure file system tools service for agent interaction.

This service provides secure file system interaction capabilities with:
- Path traversal prevention
- Async I/O wrapping
- Windows-specific security (junction points)
- Content-addressable caching
- OpenAI-compatible tool schemas for LangGraph
"""

import asyncio
import hashlib
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Any, Callable, Union
from functools import wraps
from structlog import get_logger
import mimetypes

try:
    import git
    HAS_GIT = True
except ImportError:
    HAS_GIT = False


logger = get_logger(__name__)

# Configuration
ALLOWED_DIRECTORIES = [
    Path.cwd(),  # Current workspace
    Path.home() / "Documents",  # User documents
    Path.home() / "Downloads",  # User downloads
]

MAX_FILE_SIZE = 1024 * 1024  # 1MB limit
MAX_RESULTS = 20
CACHE_DIR = Path.cwd() / ".cache"


class FileTools:
    """Secure file system interaction tools."""
    
    def __init__(self):
        self.initialized = False
        self._cache = {}
        logger.info("File tools service created")
    
    async def initialize(self):
        """Initialize file tools and cache directory."""
        CACHE_DIR.mkdir(exist_ok=True)
        self.initialized = True
        logger.info("File tools initialized", cache_dir=str(CACHE_DIR))
    
    async def close(self):
        """Close file tools and cleanup cache."""
        self._cache.clear()
        self.initialized = False
        logger.info("File tools closed")
    
    def _validate_path(self, path: Union[str, Path]) -> Path:
        """
        Validate path security and prevent traversal attacks.
        
        Args:
            path: Path to validate
            
        Returns:
            Resolved absolute Path object
            
        Raises:
            ValueError: If path is invalid or outside allowed directories
        """
        try:
            path_obj = Path(path)
            
            # Resolve to absolute path (follows symlinks)
            resolved_path = path_obj.resolve()
            
            # Check if resolved path is within allowed directories
            is_allowed = any(
                resolved_path.is_relative_to(allowed_dir)
                for allowed_dir in ALLOWED_DIRECTORIES
            )
            
            if not is_allowed:
                # Additional check: detect if original path tries to traverse
                if ".." in str(path_obj) or path_obj.is_absolute():
                    raise ValueError(f"Access denied: path outside allowed directories: {path}")
                
                # Check for Windows junction points that might escape
                if os.name == 'nt':
                    try:
                        # Check if any parent is a junction/reparse point
                        for parent in path_obj.parents:
                            if parent.is_dir() and os.path.isjunction(str(parent)):
                                raise ValueError(f"Access denied: junction point detected: {parent}")
                    except (OSError, PermissionError):
                        raise ValueError(f"Access denied: cannot verify path safety: {path}")
                
                raise ValueError(f"Access denied: path outside allowed directories: {path}")
            
            return resolved_path
            
        except (OSError, PermissionError) as e:
            raise ValueError(f"Access denied: {e}")
    
    def _get_cache_path(self, path: Path) -> Path:
        """Get cache file path for content-addressable caching."""
        path_hash = hashlib.sha256(str(path).encode()).hexdigest()
        return CACHE_DIR / f"{path_hash}.cache"
    
    async def _read_cached(self, path: Path) -> Optional[str]:
        """Read file content from cache if available and fresh."""
        cache_path = self._get_cache_path(path)
        
        if not cache_path.exists():
            return None
            
        try:
            # Check if cache is newer than file
            cache_mtime = cache_path.stat().st_mtime
            file_mtime = path.stat().st_mtime
            
            if cache_mtime >= file_mtime:
                async with asyncio.to_thread(cache_path.read_text, encoding='utf-8'):
                    return await asyncio.to_thread(cache_path.read_text, encoding='utf-8')
        except (OSError, UnicodeDecodeError):
            pass
            
        return None
    
    async def _write_cache(self, path: Path, content: str):
        """Write file content to cache."""
        cache_path = self._get_cache_path(path)
        try:
            await asyncio.to_thread(cache_path.write_text, content, encoding='utf-8')
        except OSError as e:
            logger.warning("Failed to write cache", path=str(path), error=str(e))
    
    def safe_path(self, func: Callable) -> Callable:
        """
        Decorator for automatic path validation.
        
        Automatically validates the first path argument and converts it to a Path object.
        """
        @wraps(func)
        async def wrapper(path: Union[str, Path], *args, **kwargs):
            validated_path = self._validate_path(path)
            return await func(validated_path, *args, **kwargs)
        return wrapper
    
    @safe_path
    async def list_directory(self, path: Path, pattern: str = "*", recursive: bool = False) -> List[Dict[str, Any]]:
        """
        List directory contents with metadata.
        
        Args:
            path: Directory path to list
            pattern: Glob pattern for filtering (default: "*")
            recursive: Whether to search recursively
            
        Returns:
            List of file/directory info dictionaries
        """
        if not path.is_dir():
            raise ValueError(f"Path is not a directory: {path}")
        
        try:
            # Use asyncio.to_thread for blocking glob operations
            if recursive:
                files = await asyncio.to_thread(lambda: list(path.rglob(pattern)))
            else:
                files = await asyncio.to_thread(lambda: list(path.glob(pattern)))
            
            # Limit results
            files = files[:MAX_RESULTS]
            
            result = []
            for file_path in files:
                try:
                    stat = await asyncio.to_thread(file_path.stat)
                    
                    info = {
                        "name": file_path.name,
                        "path": str(file_path),
                        "type": "directory" if file_path.is_dir() else "file",
                        "size": stat.st_size if file_path.is_file() else None,
                        "modified": stat.st_mtime,
                        "created": stat.st_ctime,
                    }
                    
                    # Human-readable size for files
                    if file_path.is_file():
                        size = stat.st_size
                        if size < 1024:
                            info["size_human"] = f"{size}B"
                        elif size < 1024 * 1024:
                            info["size_human"] = f"{size/1024:.1f}KB"
                        else:
                            info["size_human"] = f"{size/(1024*1024):.1f}MB"
                    
                    result.append(info)
                    
                except (OSError, PermissionError) as e:
                    logger.warning("Failed to stat file", path=str(file_path), error=str(e))
                    continue
            
            logger.info("Directory listed", path=str(path), count=len(result))
            return result
            
        except (OSError, PermissionError) as e:
            raise ValueError(f"Failed to list directory: {e}")
    
    @safe_path
    async def read_file(self, path: Path, start_line: Optional[int] = None, end_line: Optional[int] = None) -> Dict[str, Any]:
        """
        Read file content with optional line range.
        
        Args:
            path: File path to read
            start_line: Start line number (1-based, inclusive)
            end_line: End line number (1-based, inclusive)
            
        Returns:
            Dictionary with content, line count, and encoding info
        """
        if not path.is_file():
            raise ValueError(f"Path is not a file: {path}")
        
        # Check file size limit
        try:
            file_size = await asyncio.to_thread(path.stat().st_size)
            if file_size > MAX_FILE_SIZE:
                raise ValueError(
                    f"File too large ({file_size/1024/1024:.1f}MB). "
                    f"Use line range parameters to read specific sections."
                )
        except (OSError, PermissionError) as e:
            raise ValueError(f"Failed to access file: {e}")
        
        try:
            # Try cache first
            cached_content = await self._read_cached(path)
            if cached_content is None:
                # Read file with encoding detection
                content = await self._detect_and_read(path)
                await self._write_cache(path, content)
            else:
                content = cached_content
            
            lines = content.splitlines()
            total_lines = len(lines)
            
            # Apply line range if specified
            if start_line is not None or end_line is not None:
                start = max(1, start_line or 1) - 1  # Convert to 0-based
                end = min(total_lines, end_line or total_lines)
                
                if start >= total_lines or end <= start:
                    raise ValueError(f"Invalid line range: {start_line}-{end_line} (file has {total_lines} lines)")
                
                lines = lines[start:end]
                
                # Add line numbers
                numbered_lines = []
                for i, line in enumerate(lines, start=start + 1):
                    numbered_lines.append(f"{i:4d} | {line}")
                content = "\n".join(numbered_lines)
            else:
                # Add line numbers for full file
                numbered_lines = []
                for i, line in enumerate(lines, start=1):
                    numbered_lines.append(f"{i:4d} | {line}")
                content = "\n".join(numbered_lines)
            
            result = {
                "content": content,
                "total_lines": total_lines,
                "encoding": "utf-8",  # We force UTF-8
                "size": file_size,
                "line_range": f"{start_line or 1}-{end_line or total_lines}",
            }
            
            logger.info("File read", path=str(path), lines=total_lines, size=file_size)
            return result
            
        except UnicodeDecodeError:
            raise ValueError(f"Failed to decode file as UTF-8: {path}")
        except (OSError, PermissionError) as e:
            raise ValueError(f"Failed to read file: {e}")
    
    async def _detect_and_read(self, path: Path) -> str:
        """Read file with encoding detection (UTF-8 fallback to Latin-1)."""
        try:
            return await asyncio.to_thread(path.read_text, encoding='utf-8')
        except UnicodeDecodeError:
            # Fallback to Latin-1 for binary files
            return await asyncio.to_thread(path.read_text, encoding='latin-1')
    
    @safe_path
    async def search_files(self, path: Path, query: str, pattern: str = "*", case_sensitive: bool = False, use_regex: bool = False) -> List[Dict[str, Any]]:
        """
        Search for content in files.
        
        Args:
            path: Directory path to search in
            query: Search query string or regex pattern
            pattern: File pattern to search in (default: "*")
            case_sensitive: Whether search is case sensitive
            use_regex: Whether to treat query as regex pattern
            
        Returns:
            List of search results with context lines
        """
        if not path.is_dir():
            raise ValueError(f"Path is not a directory: {path}")
        
        # Prepare search pattern
        if use_regex:
            try:
                flags = 0 if case_sensitive else re.IGNORECASE
                search_pattern = re.compile(query, flags)
            except re.error as e:
                raise ValueError(f"Invalid regex pattern: {e}")
        else:
            search_pattern = query if case_sensitive else query.lower()
        
        try:
            # Find files matching pattern
            files = await asyncio.to_thread(lambda: list(path.rglob(pattern)))
            files = [f for f in files if f.is_file()][:MAX_RESULTS]
            
            results = []
            for file_path in files:
                try:
                    # Skip binary files and large files
                    stat = await asyncio.to_thread(file_path.stat)
                    if stat.st_size > MAX_FILE_SIZE:
                        continue
                    
                    # Try to read as text
                    try:
                        content = await self._detect_and_read(file_path)
                        lines = content.splitlines()
                    except UnicodeDecodeError:
                        continue
                    
                    # Search for matches
                    matches = []
                    for line_num, line in enumerate(lines, 1):
                        search_line = line if case_sensitive else line.lower()
                        
                        if use_regex:
                            if search_pattern.search(search_line):
                                matches.append((line_num, line))
                        else:
                            if search_pattern in search_line:
                                matches.append((line_num, line))
                    
                    if matches:
                        # Add context lines (±2)
                        context_matches = []
                        for line_num, line in matches:
                            context_start = max(1, line_num - 2)
                            context_end = min(len(lines), line_num + 2)
                            
                            context = []
                            for ctx_line_num in range(context_start, context_end + 1):
                                ctx_line = lines[ctx_line_num - 1]
                                marker = ">>> " if ctx_line_num == line_num else "    "
                                context.append(f"{marker}{ctx_line_num:4d} | {ctx_line}")
                            
                            context_matches.append({
                                "line": line_num,
                                "match": line.strip(),
                                "context": "\n".join(context),
                            })
                        
                        results.append({
                            "file": str(file_path),
                            "matches": context_matches,
                            "match_count": len(matches),
                        })
                        
                        # Limit total results
                        if len(results) >= MAX_RESULTS:
                            break
                            
                except (OSError, PermissionError, UnicodeDecodeError):
                    continue
            
            logger.info("Search completed", path=str(path), query=query, results=len(results))
            return results
            
        except (OSError, PermissionError) as e:
            raise ValueError(f"Failed to search files: {e}")
    
    @safe_path
    async def get_file_info(self, path: Path) -> Dict[str, Any]:
        """
        Get detailed file metadata.
        
        Args:
            path: File or directory path
            
        Returns:
            Dictionary with file metadata
        """
        try:
            stat = await asyncio.to_thread(path.stat)
            
            info = {
                "name": path.name,
                "path": str(path),
                "type": "directory" if path.is_dir() else "file",
                "size": stat.st_size,
                "size_human": self._format_size(stat.st_size),
                "created": stat.st_ctime,
                "modified": stat.st_mtime,
                "accessed": stat.st_atime,
                "permissions": oct(stat.st_mode)[-3:],
            }
            
            # Add file-specific info
            if path.is_file():
                # MIME type detection
                mime_type, encoding = mimetypes.guess_type(str(path))
                info["mime_type"] = mime_type
                info["encoding"] = encoding
                
                # Line count for text files
                if mime_type and mime_type.startswith('text/'):
                    try:
                        content = await self._detect_and_read(path)
                        info["line_count"] = len(content.splitlines())
                    except (UnicodeDecodeError, OSError):
                        pass
                
                # Extension info
                info["extension"] = path.suffix.lower()
            
            # Add directory-specific info
            if path.is_dir():
                try:
                    items = await asyncio.to_thread(lambda: list(path.iterdir()))
                    info["item_count"] = len(items)
                    
                    # Count files vs directories
                    files = [i for i in items if i.is_file()]
                    dirs = [i for i in items if i.is_dir()]
                    info["file_count"] = len(files)
                    info["directory_count"] = len(dirs)
                except (OSError, PermissionError):
                    pass
            
            # Windows-specific info
            if os.name == 'nt':
                info["is_junction"] = path.is_dir() and os.path.isjunction(str(path))
                info["is_symlink"] = path.is_symlink()
                if path.is_symlink():
                    try:
                        info["symlink_target"] = str(path.readlink())
                    except (OSError, PermissionError):
                        pass
            
            logger.info("File info retrieved", path=str(path))
            return info
            
        except (OSError, PermissionError) as e:
            raise ValueError(f"Failed to get file info: {e}")
    
    def _format_size(self, size: int) -> str:
        """Format file size in human-readable format."""
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024:
                return f"{size:.1f}{unit}"
            size /= 1024
        return f"{size:.1f}TB"
    
    @safe_path
    async def get_project_summary(self, path: Path) -> Dict[str, Any]:
        """
        Analyze project structure and detect project type.
        
        Args:
            path: Project directory path
            
        Returns:
            Dictionary with project analysis
        """
        if not path.is_dir():
            raise ValueError(f"Path is not a directory: {path}")
        
        try:
            # Detect project type by key files
            project_type = "unknown"
            key_files = []
            
            # Check for common project indicators
            indicators = {
                "python": ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile", ".python-version"],
                "node": ["package.json", "package-lock.json", "yarn.lock", "node_modules"],
                "rust": ["Cargo.toml", "Cargo.lock"],
                "go": ["go.mod", "go.sum", "main.go"],
                "java": ["pom.xml", "build.gradle", "src/main"],
                "dotnet": ["*.csproj", "*.sln", "packages.config"],
                "web": ["index.html", "index.htm", "default.htm"],
            }
            
            for proj_type, files in indicators.items():
                for file_pattern in files:
                    matches = await asyncio.to_thread(lambda: list(path.glob(file_pattern)))
                    if matches:
                        project_type = proj_type
                        key_files.extend([str(m) for m in matches[:3]])  # Limit to 3 files per type
                        break
                if project_type != "unknown":
                    break
            
            # Count lines of code by extension
            ext_counts = {}
            total_loc = 0
            
            # Common code file extensions
            code_extensions = {
                '.py': 'Python',
                '.js': 'JavaScript',
                '.ts': 'TypeScript',
                '.jsx': 'React',
                '.tsx': 'React TypeScript',
                '.java': 'Java',
                '.cpp': 'C++',
                '.c': 'C',
                '.cs': 'C#',
                '.rs': 'Rust',
                '.go': 'Go',
                '.php': 'PHP',
                '.rb': 'Ruby',
                '.swift': 'Swift',
                '.kt': 'Kotlin',
                '.scala': 'Scala',
                '.sh': 'Shell',
                '.bat': 'Batch',
                '.ps1': 'PowerShell',
                '.sql': 'SQL',
                '.html': 'HTML',
                '.css': 'CSS',
                '.scss': 'SCSS',
                '.less': 'Less',
                '.vue': 'Vue',
                '.svelte': 'Svelte',
            }
            
            # Count lines for each extension
            for ext, lang in code_extensions.items():
                files = await asyncio.to_thread(lambda: list(path.rglob(f"*{ext}")))
                files = [f for f in files if f.is_file()]
                
                loc = 0
                for file_path in files[:50]:  # Limit to 50 files per extension
                    try:
                        content = await self._detect_and_read(file_path)
                        loc += len(content.splitlines())
                    except (UnicodeDecodeError, OSError):
                        continue
                
                if loc > 0:
                    ext_counts[lang] = loc
                    total_loc += loc
            
            # Check for README and LICENSE
            readme_files = await asyncio.to_thread(lambda: list(path.glob("README*")))
            readme_files = [str(f) for f in readme_files if f.is_file()]
            
            license_files = await asyncio.to_thread(lambda: list(path.glob("LICENSE*")))
            license_files = [str(f) for f in license_files if f.is_file()]
            
            # Git info (if available)
            git_info = await self.get_git_info(path)
            
            summary = {
                "project_type": project_type,
                "key_files": key_files[:10],  # Limit to 10 files
                "lines_of_code": ext_counts,
                "total_loc": total_loc,
                "readme_files": readme_files,
                "license_files": license_files,
                "git_info": git_info,
                "path": str(path),
            }
            
            logger.info("Project summary generated", path=str(path), type=project_type, loc=total_loc)
            return summary
            
        except (OSError, PermissionError) as e:
            raise ValueError(f"Failed to analyze project: {e}")
    
    @safe_path
    async def get_git_info(self, path: Path) -> Optional[Dict[str, Any]]:
        """
        Get Git repository information.
        
        Args:
            path: Directory path
            
        Returns:
            Dictionary with Git info or None if not a Git repo
        """
        if not HAS_GIT:
            return None
        
        try:
            repo = await asyncio.to_thread(lambda: git.Repo(path, search_parent_directories=True))
            
            info = {
                "is_git_repo": True,
                "current_branch": repo.active_branch.name,
                "is_dirty": repo.is_dirty(),
                "total_commits": len(list(repo.iter_commits())),
            }
            
            # Get last commit info
            try:
                last_commit = repo.head.commit
                info["last_commit"] = {
                    "hash": last_commit.hexsha[:8],
                    "message": last_commit.message.strip(),
                    "author": str(last_commit.author),
                    "date": last_commit.committed_datetime.isoformat(),
                }
            except Exception:
                pass
            
            # Get remote info
            try:
                if repo.remotes:
                    origin = repo.remotes.origin
                    info["remote_url"] = origin.url
            except Exception:
                pass
            
            logger.info("Git info retrieved", path=str(path), branch=info["current_branch"])
            return info
            
        except Exception:
            return {"is_git_repo": False}
    
    # Tool schemas for LangGraph integration
    TOOL_SCHEMAS = {
        "list_directory": {
            "type": "function",
            "function": {
                "name": "list_directory",
                "description": "List files and directories in a specified path with metadata",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Directory path to list (e.g., 'C:/repos/project')"
                        },
                        "pattern": {
                            "type": "string",
                            "description": "File pattern to match (e.g., '*.py', '*.js')",
                            "default": "*"
                        },
                        "recursive": {
                            "type": "boolean",
                            "description": "Search recursively in subdirectories",
                            "default": False
                        }
                    },
                    "required": ["path"]
                }
            }
        },
        "read_file": {
            "type": "function",
            "function": {
                "name": "read_file",
                "description": "Read file content with optional line range selection",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "File path to read (e.g., 'C:/repos/project/main.py')"
                        },
                        "start_line": {
                            "type": "integer",
                            "description": "Start line number (1-based, inclusive)"
                        },
                        "end_line": {
                            "type": "integer",
                            "description": "End line number (1-based, inclusive)"
                        }
                    },
                    "required": ["path"]
                }
            }
        },
        "search_files": {
            "type": "function",
            "function": {
                "name": "search_files",
                "description": "Search for text content in files within a directory",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Directory path to search in (e.g., 'C:/repos/project')"
                        },
                        "query": {
                            "type": "string",
                            "description": "Text to search for or regex pattern"
                        },
                        "pattern": {
                            "type": "string",
                            "description": "File pattern to search in (e.g., '*.py')",
                            "default": "*"
                        },
                        "case_sensitive": {
                            "type": "boolean",
                            "description": "Whether search is case sensitive",
                            "default": False
                        },
                        "use_regex": {
                            "type": "boolean",
                            "description": "Treat query as regex pattern",
                            "default": False
                        }
                    },
                    "required": ["path", "query"]
                }
            }
        },
        "get_file_info": {
            "type": "function",
            "function": {
                "name": "get_file_info",
                "description": "Get detailed metadata about a file or directory",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "File or directory path (e.g., 'C:/repos/project/main.py')"
                        }
                    },
                    "required": ["path"]
                }
            }
        },
        "get_project_summary": {
            "type": "function",
            "function": {
                "name": "get_project_summary",
                "description": "Analyze project structure and count lines of code by language",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Project directory path (e.g., 'C:/repos/project')"
                        }
                    },
                    "required": ["path"]
                }
            }
        }
    }
