"""
Async llama.cpp client with HTTP session pooling and connection management.

This service provides a high-performance async interface to llama.cpp
server with connection pooling, circuit breaker, and proper error handling.
"""

import asyncio
import json
import time
from typing import Dict, List, Optional, AsyncGenerator, Any
from pathlib import Path

import aiohttp
import pybreaker
from structlog import get_logger

from config import settings


logger = get_logger(__name__)


class LlamaCppClientError(Exception):
    """Base exception for llama.cpp client errors."""
    pass


class LlamaCppConnectionError(LlamaCppClientError):
    """Connection-related errors."""
    pass


class LlamaCppTimeoutError(LlamaCppClientError):
    """Timeout-related errors."""
    pass


class LlamaCppInvalidResponse(LlamaCppClientError):
    """Invalid response from server."""
    pass


class CircuitBreakerState:
    """Track circuit breaker state for monitoring."""
    
    def __init__(self):
        self.failures = 0
        self.last_failure_time = None
        self.state = "CLOSED"  # CLOSED, OPEN, HALF_OPEN
    
    def record_failure(self):
        """Record a failure."""
        self.failures += 1
        self.last_failure_time = time.time()
        if self.failures >= 3:  # Threshold for opening circuit
            self.state = "OPEN"
    
    def record_success(self):
        """Record a success."""
        self.failures = 0
        self.state = "CLOSED"
    
    def should_attempt_reset(self) -> bool:
        """Check if circuit breaker should attempt reset."""
        return (
            self.state == "OPEN" and 
            self.last_failure_time and 
            time.time() - self.last_failure_time > 60  # 60 second timeout
        )


class LlamaCppClient:
    """
    Async llama.cpp client with connection pooling and circuit breaker.
    
    Features:
    - HTTP session pooling (limit=20)
    - Circuit breaker for resilience
    - 10-minute timeout for CPU inference
    - Streaming token generator with backpressure
    - Hardware-optimized request parameters
    """
    
    def __init__(
        self,
        base_url: str = "http://127.0.0.1:8080",
        max_connections: int = 20,
        timeout: int = 600,  # 10 minutes for CPU inference
        circuit_breaker_threshold: int = 3,
        circuit_breaker_timeout: int = 60,
    ):
        self.base_url = base_url.rstrip('/')
        self.max_connections = max_connections
        self.timeout = aiohttp.ClientTimeout(total=timeout)
        self.circuit_breaker_threshold = circuit_breaker_threshold
        self.circuit_breaker_timeout = circuit_breaker_timeout
        
        self._session: Optional[aiohttp.ClientSession] = None
        self._circuit_breaker = CircuitBreakerState()
        self._semaphore = asyncio.Semaphore(max_connections)
        
        # Hardware optimization settings
        self._default_params = {
            "temperature": 0.7,
            "top_p": 0.9,
            "repeat_penalty": 1.1,
            "seed": -1,  # Random seed
        }
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self.initialize()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.close()
    
    async def initialize(self):
        """Initialize HTTP session and connection pool."""
        if self._session is None:
            connector = aiohttp.TCPConnector(
                limit=self.max_connections,
                limit_per_host=self.max_connections,
                ttl_dns_cache=300,
                use_dns_cache=True,
                keepalive_timeout=60,
                enable_cleanup_closed=True,
            )
            
            self._session = aiohttp.ClientSession(
                connector=connector,
                timeout=self.timeout,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "LLM-Server/1.0",
                }
            )
            logger.info("llama.cpp client initialized", base_url=self.base_url)
    
    async def close(self):
        """Close HTTP session and cleanup resources."""
        if self._session:
            await self._session.close()
            self._session = None
            logger.info("llama.cpp client closed")
    
    def _check_circuit_breaker(self):
        """Check if circuit breaker allows requests."""
        if self._circuit_breaker.state == "OPEN":
            if self._circuit_breaker.should_attempt_reset():
                self._circuit_breaker.state = "HALF_OPEN"
                logger.info("Circuit breaker attempting reset")
            else:
                raise LlamaCppConnectionError("Circuit breaker is OPEN")
    
    def _record_success(self):
        """Record successful request."""
        self._circuit_breaker.record_success()
    
    def _record_failure(self):
        """Record failed request."""
        self._circuit_breaker.record_failure()
        logger.warning(
            "Circuit breaker failure recorded",
            failures=self._circuit_breaker.failures,
            state=self._circuit_breaker.state
        )
    
    async def _make_request(
        self,
        method: str,
        endpoint: str,
        **kwargs
    ) -> Dict[str, Any]:
        """Make HTTP request with circuit breaker and error handling."""
        self._check_circuit_breaker()
        
        if not self._session:
            await self.initialize()
        
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        
        async with self._semaphore:  # Connection limiting
            try:
                async with self._session.request(method, url, **kwargs) as response:
                    if response.status == 200:
                        self._record_success()
                        return await response.json()
                    elif response.status >= 500:
                        self._record_failure()
                        raise LlamaCppConnectionError(
                            f"Server error: {response.status} {response.reason}"
                        )
                    else:
                        raise LlamaCppInvalidResponse(
                            f"Invalid response: {response.status} {response.reason}"
                        )
            
            except aiohttp.ClientError as e:
                self._record_failure()
                raise LlamaCppConnectionError(f"Connection error: {e}")
            except asyncio.TimeoutError as e:
                self._record_failure()
                raise LlamaCppTimeoutError(f"Request timeout: {e}")
            except Exception as e:
                self._record_failure()
                raise LlamaCppClientError(f"Unexpected error: {e}")
    
    async def health_check(self) -> Dict[str, Any]:
        """Check llama.cpp server health."""
        try:
            response = await self._make_request("GET", "/health")
            return {
                "status": "healthy",
                "server_response": response,
                "circuit_breaker_state": self._circuit_breaker.state,
            }
        except Exception as e:
            return {
                "status": "unhealthy",
                "error": str(e),
                "circuit_breaker_state": self._circuit_breaker.state,
            }
    
    async def list_models(self) -> List[str]:
        """List available models."""
        try:
            response = await self._make_request("GET", "/v1/models")
            return [model["id"] for model in response.get("data", [])]
        except Exception as e:
            logger.error("Failed to list models", error=str(e))
            raise
    
    async def load_model(
        self,
        model_name: str,
        **kwargs
    ) -> Dict[str, Any]:
        """Load a model with hardware optimization."""
        # Apply hardware optimizations from config
        params = {
            **self._default_params,
            **settings.optimization_defaults.dict(),
            **kwargs,
        }
        
        # Remove incompatible parameters
        params.pop("gpu_layers", None)  # CPU-only setup
        
        payload = {
            "model": model_name,
            "options": {
                "num_threads": params["threads"],
                "ctx_size": params["context_size"],
                "batch_size": params["batch_size"],
                "temperature": params["temperature"],
                "top_p": params["top_p"],
                "repeat_penalty": params["repeat_penalty"],
                "seed": params["seed"],
            }
        }
        
        try:
            response = await self._make_request("POST", "/v1/models/load", json=payload)
            logger.info("Model loaded successfully", model=model_name)
            return response
        except Exception as e:
            logger.error("Failed to load model", model=model_name, error=str(e))
            raise
    
    async def chat_completion(
        self,
        messages: List[Dict[str, str]],
        model: str = None,
        stream: bool = False,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Create chat completion.
        
        Args:
            messages: List of message dictionaries with 'role' and 'content'
            model: Model name (uses default if None)
            stream: Whether to stream response
            **kwargs: Additional parameters
        
        Returns:
            Chat completion response
        """
        if not model:
            # Use default model from config
            model_info = settings.get_model_info("default")
            if not model_info:
                raise LlamaCppClientError("No default model configured")
            model = "default"
        
        params = {
            **self._default_params,
            **kwargs,
        }
        
        payload = {
            "model": model,
            "messages": messages,
            "temperature": params["temperature"],
            "top_p": params["top_p"],
            "repeat_penalty": params["repeat_penalty"],
            "stream": stream,
        }
        
        try:
            response = await self._make_request("POST", "/v1/chat/completions", json=payload)
            return response
        except Exception as e:
            logger.error("Chat completion failed", error=str(e))
            raise
    
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, str]],
        model: str = None,
        **kwargs
    ) -> AsyncGenerator[str, None]:
        """
        Stream chat completion tokens.
        
        Args:
            messages: List of message dictionaries
            model: Model name
            **kwargs: Additional parameters
        
        Yields:
            Token strings
        """
        if not model:
            model_info = settings.get_model_info("default")
            if not model_info:
                raise LlamaCppClientError("No default model configured")
            model = "default"
        
        params = {
            **self._default_params,
            **kwargs,
        }
        
        payload = {
            "model": model,
            "messages": messages,
            "temperature": params["temperature"],
            "top_p": params["top_p"],
            "repeat_penalty": params["repeat_penalty"],
            "stream": True,
        }
        
        self._check_circuit_breaker()
        
        if not self._session:
            await self.initialize()
        
        url = f"{self.base_url}/v1/chat/completions"
        
        async with self._semaphore:
            try:
                async with self._session.post(url, json=payload) as response:
                    if response.status != 200:
                        self._record_failure()
                        raise LlamaCppConnectionError(
                            f"Stream error: {response.status} {response.reason}"
                        )
                    
                    self._record_success()
                    
                    # Process streaming response
                    async for line in response.content:
                        line = line.decode('utf-8').strip()
                        if line.startswith('data: '):
                            data = line[6:]  # Remove 'data: ' prefix
                            if data == '[DONE]':
                                break
                            try:
                                chunk = json.loads(data)
                                if 'choices' in chunk and chunk['choices']:
                                    delta = chunk['choices'][0].get('delta', {})
                                    if 'content' in delta:
                                        yield delta['content']
                            except json.JSONDecodeError:
                                continue  # Skip malformed chunks
            
            except aiohttp.ClientError as e:
                self._record_failure()
                raise LlamaCppConnectionError(f"Stream connection error: {e}")
            except asyncio.TimeoutError as e:
                self._record_failure()
                raise LlamaCppTimeoutError(f"Stream timeout: {e}")
            except Exception as e:
                self._record_failure()
                raise LlamaCppClientError(f"Stream error: {e}")
    
    async def get_model_info(self, model: str) -> Dict[str, Any]:
        """Get information about a specific model."""
        try:
            response = await self._make_request("GET", f"/v1/models/{model}")
            return response
        except Exception as e:
            logger.error("Failed to get model info", model=model, error=str(e))
            raise
    
    def get_circuit_breaker_status(self) -> Dict[str, Any]:
        """Get circuit breaker status for monitoring."""
        return {
            "state": self._circuit_breaker.state,
            "failures": self._circuit_breaker.failures,
            "last_failure_time": self._circuit_breaker.last_failure_time,
            "threshold": self.circuit_breaker_threshold,
            "timeout": self.circuit_breaker_timeout,
        }


# Singleton instance for application use
_llamacpp_client: Optional[LlamaCppClient] = None


async def get_llamacpp_client() -> LlamaCppClient:
    """Get or create singleton llama.cpp client instance."""
    global _llamacpp_client
    if _llamacpp_client is None:
        _llamacpp_client = LlamaCppClient()
        await _llamacpp_client.initialize()
    return _llamacpp_client


async def close_llamacpp_client():
    """Close singleton llama.cpp client."""
    global _llamacpp_client
    if _llamacpp_client:
        await _llamacpp_client.close()
        _llamacpp_client = None
