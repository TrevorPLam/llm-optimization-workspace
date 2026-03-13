"""
Structured logging configuration for LLM Optimization Workspace.

Configures structlog for both development and production environments
with correlation ID support and JSON/formatted output.
"""

import logging
import sys
from typing import List

import structlog
from structlog.stdlib import LoggerFactory
from structlog.processors import TimeStamper, add_log_level, format_exc_info


def configure_logging(json_logs: bool = True, log_level: str = "INFO"):
    """
    Configure structlog for FastAPI application.
    
    Args:
        json_logs: If True, output JSON. If False, output colored console logs.
        log_level: The minimum log level to output.
    """
    # Shared processors that run for every log entry
    shared_processors: List = [
        # Add log level to the event dict
        structlog.stdlib.add_log_level,
        # Add timestamp in ISO format
        structlog.processors.TimeStamper(fmt="iso"),
        # If the log call includes exc_info, render the exception
        structlog.processors.format_exc_info,
    ]
    
    if json_logs:
        # Production: output JSON logs
        renderer = structlog.processors.JSONRenderer()
    else:
        # Development: pretty colored output
        renderer = structlog.dev.ConsoleRenderer(colors=True)
    
    structlog.configure(
        processors=shared_processors + [
            # Prepare event dict for the final renderer
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )
    
    # Configure the standard library logging to use structlog handler
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        structlog.stdlib.ProcessorFormatter(
            processor=renderer,
            foreign_pre_chain=shared_processors,
        )
    )
    
    root_logger = logging.getLogger()
    root_logger.handlers = [handler]
    root_logger.setLevel(log_level)
