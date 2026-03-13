"""
Main FastAPI application for LLM Optimization Workspace.

This module provides the core FastAPI application with:
- Lifespan management for resource initialization/cleanup
- Health check endpoints
- API security middleware
- WebSocket support with heartbeat
- Structured logging integration
- Service layer initialization
"""

import asyncio
import json
import time
import uuid
from contextlib import asynccontextmanager
from typing import Dict, List, Optional, Any

from fastapi import FastAPI, HTTPException, Depends, WebSocket, WebSocketDisconnect, Request, status, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response
import structlog
import aiofiles
from pathlib import Path

from config import settings, validate_system_requirements
from services import (
    get_service, register_service,
    LlamaCppClient, RAGEngine, AgentSystem, FileTools, HealthMonitor
)


logger = structlog.get_logger(__name__)


# Request Models
class ChatRequest(BaseModel):
    """Chat completion request model."""
    messages: List[Dict[str, str]] = Field(..., description="List of chat messages")
    model: Optional[str] = Field(None, description="Model name (uses default if not specified)")
    temperature: Optional[float] = Field(0.7, description="Sampling temperature")
    max_tokens: Optional[int] = Field(2048, description="Maximum tokens to generate")
    stream: Optional[bool] = Field(False, description="Stream response")


class ChatResponse(BaseModel):
    """Chat completion response model."""
    id: str = Field(..., description="Response ID")
    object: str = Field("chat.completion", description="Object type")
    created: int = Field(..., description="Creation timestamp")
    model: str = Field(..., description="Model used")
    choices: List[Dict[str, Any]] = Field(..., description="Response choices")
    usage: Optional[Dict[str, int]] = Field(None, description="Token usage")


class HealthResponse(BaseModel):
    """Health check response model."""
    status: str = Field(..., description="Overall health status")
    timestamp: int = Field(..., description="Response timestamp")
    version: str = Field(..., description="Application version")
    components: Dict[str, Any] = Field(..., description="Component health status")
    system: Dict[str, Any] = Field(..., description="System information")


class DocumentUploadResponse(BaseModel):
    """Document upload response model."""
    success: bool = Field(..., description="Upload success status")
    message: str = Field(..., description="Response message")
    file_name: Optional[str] = Field(None, description="Uploaded file name")
    chunks_added: Optional[int] = Field(None, description="Number of chunks added")
    processing_time: Optional[float] = Field(None, description="Processing time in seconds")
    content_hash: Optional[str] = Field(None, description="Content hash for deduplication")


class DocumentListResponse(BaseModel):
    """Document list response model."""
    success: bool = Field(..., description="Request success status")
    documents: List[Dict[str, Any]] = Field(..., description="List of documents")
    total_count: int = Field(..., description="Total number of documents")


class DocumentDeleteResponse(BaseModel):
    """Document deletion response model."""
    success: bool = Field(..., description="Deletion success status")
    message: str = Field(..., description="Response message")
    file_name: Optional[str] = Field(None, description="Deleted file name")


# WebSocket Models
class WebSocketMessage(BaseModel):
    """WebSocket message model."""
    type: str = Field(..., description="Message type")
    data: Dict[str, Any] = Field(..., description="Message data")
    timestamp: int = Field(..., description="Message timestamp")


class WebSocketManager:
    """Manage WebSocket connections with heartbeat."""
    
    def __init__(self, heartbeat_interval: int = 30):
        self.active_connections: Dict[str, WebSocket] = {}
        self.heartbeat_interval = heartbeat_interval
        self._heartbeat_task: Optional[asyncio.Task] = None
    
    async def connect(self, websocket: WebSocket, connection_id: str):
        """Accept and track WebSocket connection."""
        await websocket.accept()
        self.active_connections[connection_id] = websocket
        logger.info("WebSocket connected", connection_id=connection_id)
        
        # Start heartbeat if this is the first connection
        if len(self.active_connections) == 1:
            self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())
    
    def disconnect(self, connection_id: str):
        """Remove WebSocket connection."""
        if connection_id in self.active_connections:
            del self.active_connections[connection_id]
            logger.info("WebSocket disconnected", connection_id=connection_id)
        
        # Stop heartbeat if no connections
        if len(self.active_connections) == 0 and self._heartbeat_task:
            self._heartbeat_task.cancel()
            self._heartbeat_task = None
    
    async def send_personal_message(self, connection_id: str, message: dict):
        """Send message to specific connection."""
        if connection_id in self.active_connections:
            websocket = self.active_connections[connection_id]
            try:
                await websocket.send_json(message)
            except Exception as e:
                logger.error("Failed to send WebSocket message", connection_id=connection_id, error=str(e))
                self.disconnect(connection_id)
    
    async def broadcast(self, message: dict):
        """Broadcast message to all connections."""
        disconnected = []
        for connection_id, websocket in self.active_connections.items():
            try:
                await websocket.send_json(message)
            except Exception as e:
                logger.error("Failed to broadcast WebSocket message", connection_id=connection_id, error=str(e))
                disconnected.append(connection_id)
        
        # Clean up disconnected connections
        for connection_id in disconnected:
            self.disconnect(connection_id)
    
    async def _heartbeat_loop(self):
        """Send periodic heartbeat to all connections."""
        while self.active_connections:
            try:
                heartbeat = {
                    "type": "heartbeat",
                    "timestamp": int(time.time()),
                    "data": {"connections": len(self.active_connections)}
                }
                await self.broadcast(heartbeat)
                await asyncio.sleep(self.heartbeat_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Heartbeat error", error=str(e))
                await asyncio.sleep(5)  # Wait before retry


# Security
security = HTTPBearer(auto_error=False)


async def verify_api_key(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)
) -> Optional[str]:
    """Verify API key for authentication."""
    if not settings.security.enable_auth:
        return None  # Skip authentication if disabled
    
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="API key required",
        )
    
    if credentials.scheme != "Bearer":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid authentication scheme",
        )
    
    # Check against configured API key
    if credentials.credentials != settings.security.api_key:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid API key",
        )
    
    return credentials.credentials


# Middleware
class CorrelationIDMiddleware(BaseHTTPMiddleware):
    """Add correlation ID to requests for tracing."""
    
    async def dispatch(self, request: Request, call_next):
        correlation_id = request.headers.get("X-Correlation-ID") or str(uuid.uuid4())
        request.state.correlation_id = correlation_id
        
        # Add to logger context
        logger = structlog.get_logger()
        logger = logger.bind(correlation_id=correlation_id)
        
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        return response


class LoggingMiddleware(BaseHTTPMiddleware):
    """Request/response logging middleware."""
    
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        
        # Log request
        logger.info(
            "Request started",
            method=request.method,
            url=str(request.url),
            client_ip=request.client.host if request.client else None,
            correlation_id=getattr(request.state, "correlation_id", None),
        )
        
        # Process request
        response = await call_next(request)
        
        # Log response
        process_time = time.time() - start_time
        logger.info(
            "Request completed",
            status_code=response.status_code,
            process_time=f"{process_time:.3f}s",
            correlation_id=getattr(request.state, "correlation_id", None),
        )
        
        return response


# Lifespan Management
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    logger.info("Application startup initiated")
    
    # Validate system requirements
    system_validation = validate_system_requirements()
    if not system_validation["valid"]:
        logger.error("System requirements not met", warnings=system_validation["warnings"])
        raise RuntimeError("System requirements not met")
    
    logger.info("System requirements validated", system=system_validation)
    
    # Initialize services
    try:
        # Initialize llama.cpp client
        llamacpp_client = LlamaCppClient()
        await llamacpp_client.initialize()
        register_service("llamacpp_client", llamacpp_client)
        logger.info("llama.cpp client initialized")
        
        # Initialize health monitor
        health_monitor = HealthMonitor()
        await health_monitor.initialize()
        register_service("health_monitor", health_monitor)
        logger.info("Health monitor initialized")
        
        # Initialize other services (will be implemented in later tasks)
        # RAG engine and agent system will be initialized when needed
        
        # Store services in app state
        app.state.llamacpp_client = llamacpp_client
        app.state.health_monitor = health_monitor
        app.state.websocket_manager = WebSocketManager()
        
        logger.info("All services initialized successfully")
        
    except Exception as e:
        logger.error("Failed to initialize services", error=str(e))
        raise
    
    # Application startup complete
    logger.info("Application startup complete")
    
    yield
    
    # Shutdown cleanup
    logger.info("Application shutdown initiated")
    
    try:
        # Close WebSocket connections
        if hasattr(app.state, 'websocket_manager'):
            # Force disconnect all connections
            app.state.websocket_manager.active_connections.clear()
        
        # Close services
        if hasattr(app.state, 'llamacpp_client'):
            await app.state.llamacpp_client.close()
        
        if hasattr(app.state, 'health_monitor'):
            await app.state.health_monitor.close()
        
        logger.info("All services closed successfully")
        
    except Exception as e:
        logger.error("Error during shutdown", error=str(e))
    
    logger.info("Application shutdown complete")


# Create FastAPI application
app = FastAPI(
    title="LLM Optimization Server",
    description="Production-ready LLM server with FastAPI, ChromaDB, and LangGraph",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.environment == "development" else None,
    redoc_url="/redoc" if settings.environment == "development" else None,
)

# Add middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.security.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(CorrelationIDMiddleware)
app.add_middleware(LoggingMiddleware)

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")


# Health Endpoints
@app.get("/api/health", response_model=HealthResponse)
async def health_check():
    """Comprehensive health check endpoint."""
    timestamp = int(time.time())
    components = {}
    
    # Check llama.cpp client
    if hasattr(app.state, 'llamacpp_client'):
        llamacpp_health = await app.state.llamacpp_client.health_check()
        components["llamacpp"] = llamacpp_health
    else:
        components["llamacpp"] = {"status": "not_initialized"}
    
    # Check health monitor
    if hasattr(app.state, 'health_monitor'):
        health_status = await app.state.health_monitor.get_status()
        components["health_monitor"] = health_status
    else:
        components["health_monitor"] = {"status": "not_initialized"}
    
    # Check WebSocket connections
    if hasattr(app.state, 'websocket_manager'):
        components["websocket"] = {
            "status": "active",
            "connections": len(app.state.websocket_manager.active_connections)
        }
    else:
        components["websocket"] = {"status": "not_initialized"}
    
    # Overall status
    overall_status = "healthy"
    for component in components.values():
        if component.get("status") == "unhealthy":
            overall_status = "degraded"
        elif component.get("status") == "not_initialized":
            overall_status = "starting"
    
    return HealthResponse(
        status=overall_status,
        timestamp=timestamp,
        version="1.0.0",
        components=components,
        system=validate_system_requirements()
    )


@app.get("/api/health/ready")
async def readiness_check():
    """Readiness probe for Kubernetes/container orchestration."""
    # Check if critical services are ready
    if not hasattr(app.state, 'llamacpp_client'):
        raise HTTPException(status_code=503, detail="llama.cpp client not ready")
    
    llamacpp_health = await app.state.llamacpp_client.health_check()
    if llamacpp_health["status"] != "healthy":
        raise HTTPException(status_code=503, detail="llama.cpp server not healthy")
    
    return {"status": "ready"}


@app.get("/api/health/live")
async def liveness_check():
    """Liveness probe for Kubernetes/container orchestration."""
    return {"status": "alive", "timestamp": int(time.time())}


# Chat Endpoints
@app.post("/api/chat/completions", response_model=ChatResponse)
async def chat_completions(
    request: ChatRequest,
    api_key: Optional[str] = Depends(verify_api_key)
):
    """Create chat completion."""
    try:
        llamacpp_client = app.state.llamacpp_client
        
        # Convert request format
        response = await llamacpp_client.chat_completion(
            messages=request.messages,
            model=request.model,
            temperature=request.temperature,
            max_tokens=request.max_tokens,
            stream=request.stream
        )
        
        # Convert to our response format
        return ChatResponse(
            id=response.get("id", str(uuid.uuid4())),
            object="chat.completion",
            created=response.get("created", int(time.time())),
            model=response.get("model", request.model or "default"),
            choices=response.get("choices", []),
            usage=response.get("usage")
        )
    
    except Exception as e:
        logger.error("Chat completion failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/chat/completions/stream")
async def chat_completions_stream(
    request: ChatRequest,
    api_key: Optional[str] = Depends(verify_api_key)
):
    """Stream chat completion."""
    try:
        llamacpp_client = app.state.llamacpp_client
        
        async def generate():
            async for token in llamacpp_client.chat_completion_stream(
                messages=request.messages,
                model=request.model,
                temperature=request.temperature,
                max_tokens=request.max_tokens
            ):
                yield f"data: {json.dumps({'choices': [{'delta': {'content': token}}]})}\n\n"
            yield "data: [DONE]\n\n"
        
        return Response(
            generate(),
            media_type="text/plain",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "Content-Type": "text/event-stream",
            }
        )
    
    except Exception as e:
        logger.error("Chat completion stream failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))


# WebSocket Endpoint
@app.websocket("/ws/chat")
async def websocket_chat(websocket: WebSocket):
    """WebSocket endpoint for real-time chat."""
    connection_id = str(uuid.uuid4())
    manager = app.state.websocket_manager
    
    try:
        await manager.connect(websocket, connection_id)
        
        while True:
            # Receive message
            data = await websocket.receive_json()
            message_type = data.get("type", "unknown")
            
            if message_type == "ping":
                # Heartbeat response
                await manager.send_personal_message(connection_id, {
                    "type": "pong",
                    "timestamp": int(time.time())
                })
            elif message_type == "chat":
                # Handle chat message
                try:
                    llamacpp_client = app.state.llamacpp_client
                    messages = data.get("messages", [])
                    
                    # Stream response
                    await manager.send_personal_message(connection_id, {
                        "type": "chat_start",
                        "timestamp": int(time.time())
                    })
                    
                    async for token in llamacpp_client.chat_completion_stream(
                        messages=messages,
                        model=data.get("model"),
                        temperature=data.get("temperature", 0.7)
                    ):
                        await manager.send_personal_message(connection_id, {
                            "type": "chat_token",
                            "data": {"content": token},
                            "timestamp": int(time.time())
                        })
                    
                    await manager.send_personal_message(connection_id, {
                        "type": "chat_end",
                        "timestamp": int(time.time())
                    })
                
                except Exception as e:
                    await manager.send_personal_message(connection_id, {
                        "type": "error",
                        "data": {"error": str(e)},
                        "timestamp": int(time.time())
                    })
            else:
                # Unknown message type
                await manager.send_personal_message(connection_id, {
                    "type": "error",
                    "data": {"error": f"Unknown message type: {message_type}"},
                    "timestamp": int(time.time())
                })
    
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected normally", connection_id=connection_id)
    except Exception as e:
        logger.error("WebSocket error", connection_id=connection_id, error=str(e))
    finally:
        manager.disconnect(connection_id)


# Root endpoint
@app.get("/")
async def root():
    """Serve the frontend application."""
    return FileResponse("static/index.html", media_type="text/html")


@app.get("/api")
async def api_info():
    """API information endpoint."""
    return {
        "name": "LLM Optimization Server",
        "version": "1.0.0",
        "environment": settings.environment,
        "docs": "/docs" if settings.environment == "development" else None,
        "health": "/api/health"
    }


@app.get("/api/models")
async def get_models():
    """Get available models for the frontend."""
    # For now, return a mock list of models
    return [
        {"name": "llama-3.2-1b", "size": "771MB"},
        {"name": "qwen2.5-1.5b", "size": "1.04GB"},
        {"name": "qwen2.5-coder-1.5b", "size": "778MB"},
        {"name": "smolLM2-1.7b", "size": "1.01GB"},
        {"name": "phi-4-mini", "size": "2.38GB"},
        {"name": "gemma-3-4b", "size": "2.37GB"},
        {"name": "qwen3-4b", "size": "2.38GB"},
        {"name": "deepseek-r1-distill-qwen-14b", "size": "1.11GB"}
    ]


# Document Management Endpoints
@app.post("/api/documents/upload", response_model=DocumentUploadResponse)
async def upload_document(
    file: UploadFile = File(...),
    api_key: Optional[str] = Depends(verify_api_key)
):
    """Upload and process a document for RAG indexing."""
    try:
        # Validate file type
        allowed_extensions = {'.pdf', '.docx', '.txt', '.md', '.py', '.js', '.html', '.css', '.json', '.xml', '.yaml', '.yml'}
        file_extension = Path(file.filename).suffix.lower()

        if file_extension not in allowed_extensions:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported file type: {file_extension}. Supported types: {', '.join(allowed_extensions)}"
            )

        # Create uploads directory if it doesn't exist
        uploads_dir = Path("uploads")
        uploads_dir.mkdir(exist_ok=True)

        # Save uploaded file
        file_path = uploads_dir / file.filename

        async with aiofiles.open(file_path, 'wb') as f:
            content = await file.read()
            await f.write(content)

        logger.info("File uploaded", file_name=file.filename, file_size=len(content))

        # Get RAG engine service
        rag_engine = get_service("rag_engine")
        if not rag_engine or not rag_engine.initialized:
            raise HTTPException(status_code=503, detail="RAG engine not available")

        # Process document
        result = await rag_engine.add_document(str(file_path))

        if result["success"]:
            return DocumentUploadResponse(
                success=True,
                message="Document uploaded and indexed successfully",
                file_name=file.filename,
                chunks_added=result["chunks_added"],
                processing_time=result["processing_time"],
                content_hash=result["content_hash"]
            )
        else:
            # Clean up failed upload
            if file_path.exists():
                file_path.unlink()

            return DocumentUploadResponse(
                success=False,
                message=result["error"],
                file_name=file.filename
            )

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Document upload failed", file_name=file.filename, error=str(e))
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")


@app.get("/api/documents", response_model=DocumentListResponse)
async def get_documents(api_key: Optional[str] = Depends(verify_api_key)):
    """Get list of all indexed documents."""
    try:
        rag_engine = get_service("rag_engine")
        if not rag_engine or not rag_engine.initialized:
            raise HTTPException(status_code=503, detail="RAG engine not available")

        documents = await rag_engine.get_document_list()

        return DocumentListResponse(
            success=True,
            documents=documents,
            total_count=len(documents)
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get document list", error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to retrieve documents: {str(e)}")


@app.delete("/api/documents/{file_name}", response_model=DocumentDeleteResponse)
async def delete_document(
    file_name: str,
    api_key: Optional[str] = Depends(verify_api_key)
):
    """Delete a document from the RAG system."""
    try:
        rag_engine = get_service("rag_engine")
        if not rag_engine or not rag_engine.initialized:
            raise HTTPException(status_code=503, detail="RAG engine not available")

        # Find the file in uploads directory
        uploads_dir = Path("uploads")
        file_path = uploads_dir / file_name

        if not file_path.exists():
            raise HTTPException(status_code=404, detail="Document not found")

        # Delete from RAG engine
        result = await rag_engine.delete_document(str(file_path))

        if result["success"]:
            # Remove actual file
            if file_path.exists():
                file_path.unlink()

            return DocumentDeleteResponse(
                success=True,
                message="Document deleted successfully",
                file_name=file_name
            )
        else:
            return DocumentDeleteResponse(
                success=False,
                message=result["error"],
                file_name=file_name
            )

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Document deletion failed", file_name=file_name, error=str(e))
        raise HTTPException(status_code=500, detail=f"Deletion failed: {str(e)}")


@app.get("/api/documents/stats")
async def get_document_stats(api_key: Optional[str] = Depends(verify_api_key)):
    """Get RAG system statistics."""
    try:
        rag_engine = get_service("rag_engine")
        if not rag_engine or not rag_engine.initialized:
            raise HTTPException(status_code=503, detail="RAG engine not available")

        stats = await rag_engine.get_stats()
        return stats

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get document stats", error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to retrieve stats: {str(e)}")


@app.post("/api/documents/search")
async def search_documents(
    request: dict = {"query": "", "top_k": 5},
    api_key: Optional[str] = Depends(verify_api_key)
):
    """Search for documents using RAG."""
    try:
        query = request.get("query", "")
        top_k = request.get("top_k", 5)

        if not query:
            raise HTTPException(status_code=400, detail="Query parameter is required")

        rag_engine = get_service("rag_engine")
        if not rag_engine or not rag_engine.initialized:
            raise HTTPException(status_code=503, detail="RAG engine not available")

        results = await rag_engine.search(query, top_k)

        return {
            "success": True,
            "query": query,
            "results": results,
            "total_results": len(results)
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Document search failed", query=request.get("query", ""), error=str(e))
        raise HTTPException(status_code=500, detail=f"Search failed: {str(e)}")


# Error handlers
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Handle HTTP exceptions."""
    logger.error(
        "HTTP exception",
        status_code=exc.status_code,
        detail=exc.detail,
        correlation_id=getattr(request.state, "correlation_id", None)
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail, "status_code": exc.status_code}
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle general exceptions."""
    logger.error(
        "Unhandled exception",
        error=str(exc),
        correlation_id=getattr(request.state, "correlation_id", None)
    )
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error", "status_code": 500}
    )


if __name__ == "__main__":
    import uvicorn
    
    # Configure structured logging
    import logging_config
    logging_config.configure_logging(
        json_logs=settings.is_production(),
        log_level=settings.server.log_level
    )
    
    uvicorn.run(
        "main:app",
        host=settings.server.host,
        port=settings.server.port,
        reload=settings.server.reload,
        log_level=settings.server.log_level.lower(),
    )
