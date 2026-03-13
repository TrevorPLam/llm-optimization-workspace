"""
Services module for LLM Optimization Workspace.

This module provides core services for:
- llama.cpp client integration
- ChromaDB vector storage
- LangGraph agent system
- RAG engine
- File system tools
- Health monitoring

All services are designed with async/await patterns and proper
resource management for production use.
"""

from .llamacpp_client import LlamaCppClient
from .rag_engine import RAGEngine
from .agent_system import AgentSystem
from .file_tools import FileTools
from .health_monitor import HealthMonitor

__all__ = [
    "LlamaCppClient",
    "RAGEngine", 
    "AgentSystem",
    "FileTools",
    "HealthMonitor",
]

# Service registry for lazy initialization
_service_registry = {}

def get_service(service_name: str):
    """Get service instance from registry."""
    return _service_registry.get(service_name)

def register_service(service_name: str, service_instance):
    """Register service instance."""
    _service_registry[service_name] = service_instance

def clear_services():
    """Clear all service instances (useful for testing)."""
    _service_registry.clear()
