"""
Health monitoring service for LLM Optimization Workspace.

Provides system health monitoring, metrics collection, and
component status tracking for production observability.
"""

import asyncio
import psutil
import time
from typing import Dict, Any, Optional

from structlog import get_logger


logger = get_logger(__name__)


class HealthMonitor:
    """Monitor system health and component status."""
    
    def __init__(self):
        self.start_time = time.time()
        self._metrics = {}
        self._component_status = {}
        self._running = False
    
    async def initialize(self):
        """Initialize health monitoring."""
        self._running = True
        logger.info("Health monitor initialized")
    
    async def close(self):
        """Close health monitor."""
        self._running = False
        logger.info("Health monitor closed")
    
    async def get_status(self) -> Dict[str, Any]:
        """Get comprehensive health status."""
        return {
            "status": "healthy",
            "uptime_seconds": int(time.time() - self.start_time),
            "timestamp": int(time.time()),
            "system": await self._get_system_metrics(),
            "components": self._component_status,
            "metrics": self._metrics,
        }
    
    async def _get_system_metrics(self) -> Dict[str, Any]:
        """Get system performance metrics."""
        try:
            # CPU metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_count = psutil.cpu_count(logical=False)
            cpu_freq = psutil.cpu_freq()
            
            # Memory metrics
            memory = psutil.virtual_memory()
            
            # Disk metrics
            disk = psutil.disk_usage('.')
            
            # Network metrics
            network = psutil.net_io_counters()
            
            return {
                "cpu": {
                    "percent": cpu_percent,
                    "count": cpu_count,
                    "frequency": {
                        "current": cpu_freq.current if cpu_freq else None,
                        "min": cpu_freq.min if cpu_freq else None,
                        "max": cpu_freq.max if cpu_freq else None,
                    } if cpu_freq else None,
                },
                "memory": {
                    "total": memory.total,
                    "available": memory.available,
                    "percent": memory.percent,
                    "used": memory.used,
                    "free": memory.free,
                },
                "disk": {
                    "total": disk.total,
                    "used": disk.used,
                    "free": disk.free,
                    "percent": (disk.used / disk.total) * 100,
                },
                "network": {
                    "bytes_sent": network.bytes_sent if network else 0,
                    "bytes_recv": network.bytes_recv if network else 0,
                    "packets_sent": network.packets_sent if network else 0,
                    "packets_recv": network.packets_recv if network else 0,
                } if network else None,
            }
        except Exception as e:
            logger.error("Failed to get system metrics", error=str(e))
            return {"error": str(e)}
    
    def register_component(self, name: str, status: str, details: Optional[Dict[str, Any]] = None):
        """Register component status."""
        self._component_status[name] = {
            "status": status,
            "timestamp": int(time.time()),
            "details": details or {},
        }
    
    def update_metric(self, name: str, value: Any):
        """Update a metric value."""
        self._metrics[name] = {
            "value": value,
            "timestamp": int(time.time()),
        }
