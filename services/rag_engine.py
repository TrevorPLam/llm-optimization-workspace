"""
RAG (Retrieval Augmented Generation) engine service.

This service provides document ingestion, vector storage, and
retrieval capabilities for the LLM system with ChromaDB 1.5.x integration.
"""

import asyncio
import hashlib
import json
import sqlite3
import time
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple

import chromadb
import structlog
from chromadb.config import Settings as ChromaSettings
from chromadb.utils import embedding_functions

from .document_processor import document_processor, ExtractedContent, DocumentMetadata


logger = structlog.get_logger(__name__)


class RAGEngine:
    """RAG engine for document processing and retrieval."""
    
    def __init__(self, db_path: str = "chroma_db", metadata_db: str = "rag_metadata.db"):
        self.db_path = Path(db_path)
        self.metadata_db_path = Path(metadata_db)
        self.client = None
        self.collection = None
        self.embedding_function = None
        self.initialized = False
        
        # ChromaDB 1.5.x HNSW configuration
        self.hnsw_config = {
            "space": "cosine",  # Best for semantic similarity
            "ef_construction": 200,  # Better index quality
            "ef_search": 100,  # Default search accuracy
            "max_neighbors": 16,  # Balanced setting
            "num_threads": 6,  # Optimized for i5-9500
            "batch_size": 100,
            "sync_threshold": 1000,
            "resize_factor": 1.2
        }
        
        logger.info("RAG engine service created", db_path=str(self.db_path))
    
    async def initialize(self):
        """Initialize RAG engine with ChromaDB 1.5.x."""
        try:
            # Initialize ChromaDB client
            self.client = chromadb.PersistentClient(
                path=str(self.db_path),
                settings=ChromaSettings(
                    anonymized_telemetry=False,
                    allow_reset=False
                )
            )
            
            # Initialize embedding function (using default for now)
            self.embedding_function = embedding_functions.DefaultEmbeddingFunction()
            
            # Get or create collection with HNSW configuration
            try:
                self.collection = self.client.get_collection(
                    name="knowledge_base",
                    embedding_function=self.embedding_function
                )
                logger.info("Existing collection loaded")
            except Exception:
                # Create new collection without HNSW config for now
                self.collection = self.client.create_collection(
                    name="knowledge_base",
                    embedding_function=self.embedding_function
                )
                logger.info("New collection created")
            
            # Initialize metadata database
            await self._init_metadata_db()
            
            self.initialized = True
            logger.info("RAG engine initialized successfully")
            
        except Exception as e:
            logger.error("Failed to initialize RAG engine", error=str(e))
            raise
    
    async def close(self):
        """Close RAG engine and cleanup resources."""
        try:
            if self.client:
                # ChromaDB client doesn't need explicit closing in persistent mode
                pass
            
            self.initialized = False
            logger.info("RAG engine closed")
            
        except Exception as e:
            logger.error("Error closing RAG engine", error=str(e))
    
    async def add_document(self, file_path: str, metadata: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Add document to vector store with intelligent chunking."""
        if not self.initialized:
            raise RuntimeError("RAG engine not initialized")
        
        start_time = time.time()
        file_path = Path(file_path)
        
        try:
            logger.info("Adding document to RAG engine", file_path=str(file_path))
            
            # Process document
            extracted_content = await document_processor.process_document(file_path)
            
            if not extracted_content.metadata.extraction_success:
                logger.error("Document processing failed", 
                           file_path=str(file_path), 
                           error=extracted_content.metadata.error_message)
                return {
                    "success": False,
                    "error": extracted_content.metadata.error_message,
                    "file_path": str(file_path)
                }
            
            # Check for duplicates using content hash
            if await self._is_duplicate(extracted_content.metadata.content_hash):
                logger.info("Document already exists (duplicate content)", 
                           file_path=str(file_path))
                return {
                    "success": False,
                    "error": "Document already indexed (duplicate content)",
                    "file_path": str(file_path)
                }
            
            # Chunk the document
            chunks = await self._chunk_document(extracted_content)
            
            if not chunks:
                logger.warning("No chunks generated from document", 
                             file_path=str(file_path))
                return {
                    "success": False,
                    "error": "No content to index",
                    "file_path": str(file_path)
                }
            
            # Generate embeddings in batches
            embeddings = await self._generate_embeddings_batch(chunks)
            
            # Prepare documents for ChromaDB
            documents = [chunk["text"] for chunk in chunks]
            metadatas = [chunk["metadata"] for chunk in chunks]
            ids = [chunk["id"] for chunk in chunks]
            
            # Add to ChromaDB
            self.collection.add(
                documents=documents,
                metadatas=metadatas,
                ids=ids,
                embeddings=embeddings
            )
            
            # Store metadata in SQLite
            await self._store_document_metadata(extracted_content, len(chunks))
            
            processing_time = time.time() - start_time
            
            logger.info("Document added successfully", 
                       file_path=str(file_path),
                       chunks=len(chunks),
                       processing_time=processing_time)
            
            return {
                "success": True,
                "file_path": str(file_path),
                "chunks_added": len(chunks),
                "processing_time": processing_time,
                "content_hash": extracted_content.metadata.content_hash
            }
            
        except Exception as e:
            logger.error("Failed to add document", 
                       file_path=str(file_path), 
                       error=str(e))
            return {
                "success": False,
                "error": str(e),
                "file_path": str(file_path)
            }
    
    async def search(self, query: str, top_k: int = 5, ef_search: Optional[int] = None) -> List[Dict[str, Any]]:
        """Search for relevant documents with dynamic accuracy control."""
        if not self.initialized:
            raise RuntimeError("RAG engine not initialized")
        
        try:
            # Adjust search accuracy based on query complexity
            if ef_search is None:
                ef_search = self._calculate_ef_search(query)
            
            # Update collection ef_search temporarily
            original_ef = 100  # Default value
            
            try:
                # Note: ChromaDB doesn't support runtime ef_search modification in current version
                # This would be implemented when the feature becomes available
                
                # Perform search
                results = self.collection.query(
                    query_texts=[query],
                    n_results=top_k,
                    include=["documents", "metadatas", "distances"]
                )
                
                # Format results
                formatted_results = []
                if results["documents"] and results["documents"][0]:
                    for i in range(len(results["documents"][0])):
                        formatted_results.append({
                            "content": results["documents"][0][i],
                            "metadata": results["metadatas"][0][i],
                            "distance": results["distances"][0][i],
                            "similarity": 1 - results["distances"][0][i]  # Convert to similarity
                        })
                
                logger.info("Search completed", 
                           query=query[:50] + "..." if len(query) > 50 else query,
                           results=len(formatted_results),
                           ef_search=ef_search)
                
                return formatted_results
                
            finally:
                # Restore original ef_search if we modified it
                pass
                
        except Exception as e:
            logger.error("Search failed", query=query[:50], error=str(e))
            return []
    
    async def _init_metadata_db(self):
        """Initialize SQLite database for document metadata."""
        def _init_sync():
            conn = sqlite3.connect(str(self.metadata_db_path))
            cursor = conn.cursor()
            
            # Create documents table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS documents (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_path TEXT UNIQUE NOT NULL,
                    file_name TEXT NOT NULL,
                    file_size INTEGER NOT NULL,
                    file_type TEXT NOT NULL,
                    content_hash TEXT UNIQUE NOT NULL,
                    extraction_method TEXT NOT NULL,
                    page_count INTEGER,
                    chunk_count INTEGER NOT NULL,
                    processing_time REAL,
                    virus_scan_result TEXT,
                    extraction_success BOOLEAN NOT NULL,
                    error_message TEXT,
                    indexed_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Create indexes
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_content_hash ON documents(content_hash)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_file_path ON documents(file_path)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_indexed_date ON documents(indexed_date)")
            
            conn.commit()
            conn.close()
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _init_sync)
        
        logger.info("Metadata database initialized", db_path=str(self.metadata_db_path))
    
    async def _is_duplicate(self, content_hash: str) -> bool:
        """Check if document with same content hash already exists."""
        def _check_sync():
            conn = sqlite3.connect(str(self.metadata_db_path))
            cursor = conn.cursor()
            
            cursor.execute("SELECT 1 FROM documents WHERE content_hash = ?", (content_hash,))
            result = cursor.fetchone()
            
            conn.close()
            return result is not None
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _check_sync)
    
    async def _chunk_document(self, extracted_content: ExtractedContent) -> List[Dict[str, Any]]:
        """Chunk document using RecursiveCharacterTextSplitter strategy."""
        text = extracted_content.text
        metadata = extracted_content.metadata
        
        # Chunking configuration based on 2026 research
        chunk_size = 512  # Optimal for most models
        chunk_overlap = 50  # ~10% overlap
        
        chunks = []
        chunk_id = 0
        
        # Simple recursive character splitting
        separators = ["\n\n", "\n", " ", ""]
        
        def _recursive_split(text: str, separators: List[str], chunk_size: int, chunk_overlap: int) -> List[str]:
            """Recursively split text using separators."""
            if not text:
                return []
            
            # Try each separator in order
            for separator in separators:
                if separator in text:
                    # Split by this separator
                    parts = text.split(separator)
                    chunks = []
                    current_chunk = ""
                    
                    for part in parts:
                        if len(current_chunk) + len(part) + len(separator) <= chunk_size:
                            current_chunk += (separator if current_chunk else "") + part
                        else:
                            if current_chunk:
                                chunks.append(current_chunk)
                            current_chunk = part
                    
                    if current_chunk:
                        chunks.append(current_chunk)
                    
                    # If any chunk is still too large, recurse with next separator
                    if any(len(chunk) > chunk_size for chunk in chunks) and len(separators) > 1:
                        result_chunks = []
                        for chunk in chunks:
                            if len(chunk) > chunk_size:
                                result_chunks.extend(_recursive_split(chunk, separators[1:], chunk_size, chunk_overlap))
                            else:
                                result_chunks.append(chunk)
                        return result_chunks
                    
                    return chunks
            
            # No separators found, split by character
            chunks = []
            for i in range(0, len(text), chunk_size - chunk_overlap):
                chunks.append(text[i:i + chunk_size])
            return chunks
        
        # Generate chunks
        text_chunks = _recursive_split(text, separators, chunk_size, chunk_overlap)
        
        # Create chunk objects with metadata
        for i, chunk_text in enumerate(text_chunks):
            if chunk_text.strip():  # Skip empty chunks
                chunk_id = f"{metadata.content_hash}_{i}"
                
                chunk_metadata = {
                    "document_id": metadata.content_hash,
                    "chunk_index": i,
                    "source_file": metadata.file_name,
                    "file_path": metadata.file_path,
                    "file_type": metadata.file_type,
                    "extraction_method": metadata.extraction_method,
                    "chunk_size": len(chunk_text),
                    "total_chunks": len(text_chunks)
                }
                
                chunks.append({
                    "id": chunk_id,
                    "text": chunk_text.strip(),
                    "metadata": chunk_metadata
                })
        
        logger.info("Document chunked", 
                   file_path=metadata.file_path,
                   total_chunks=len(chunks),
                   avg_chunk_size=sum(len(c["text"]) for c in chunks) // len(chunks) if chunks else 0)
        
        return chunks
    
    async def _generate_embeddings_batch(self, chunks: List[Dict[str, Any]], batch_size: int = 32) -> List[List[float]]:
        """Generate embeddings for chunks in batches."""
        texts = [chunk["text"] for chunk in chunks]
        embeddings = []
        
        # Process in batches to avoid overwhelming the system
        for i in range(0, len(texts), batch_size):
            batch_texts = texts[i:i + batch_size]
            
            try:
                # Generate embeddings using ChromaDB's embedding function
                batch_embeddings = self.embedding_function(batch_texts)
                embeddings.extend(batch_embeddings)
                
                logger.debug("Embedding batch completed", 
                           batch_start=i, 
                           batch_end=min(i + batch_size, len(texts)))
                
            except Exception as e:
                logger.error("Embedding generation failed", batch_start=i, error=str(e))
                # Add zero embeddings as fallback
                zero_embedding = [0.0] * 384  # Default embedding dimension
                embeddings.extend([zero_embedding] * len(batch_texts))
        
        return embeddings
    
    async def _store_document_metadata(self, extracted_content: ExtractedContent, chunk_count: int):
        """Store document metadata in SQLite database."""
        def _store_sync():
            conn = sqlite3.connect(str(self.metadata_db_path))
            cursor = conn.cursor()
            
            metadata = extracted_content.metadata
            
            cursor.execute("""
                INSERT OR REPLACE INTO documents 
                (file_path, file_name, file_size, file_type, content_hash, 
                 extraction_method, page_count, chunk_count, processing_time,
                 virus_scan_result, extraction_success, error_message)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                metadata.file_path,
                metadata.file_name,
                metadata.file_size,
                metadata.file_type,
                metadata.content_hash,
                metadata.extraction_method,
                metadata.page_count,
                chunk_count,
                metadata.processing_time,
                metadata.virus_scan_result,
                metadata.extraction_success,
                metadata.error_message
            ))
            
            conn.commit()
            conn.close()
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _store_sync)
    
    def _calculate_ef_search(self, query: str) -> int:
        """Calculate optimal ef_search based on query complexity."""
        query_length = len(query.split())
        
        # Dynamic adjustment based on research findings
        if query_length <= 3:  # Short queries
            return 10  # Faster search
        elif query_length <= 10:  # Medium queries
            return 50  # Balanced
        elif query_length <= 20:  # Long queries
            return 200  # Higher accuracy
        else:  # Very long queries
            return 500  # Maximum accuracy
    
    async def get_document_list(self) -> List[Dict[str, Any]]:
        """Get list of all indexed documents."""
        def _get_docs_sync():
            conn = sqlite3.connect(str(self.metadata_db_path))
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT file_name, file_size, file_type, chunk_count, 
                       processing_time, indexed_date, extraction_success
                FROM documents 
                WHERE extraction_success = TRUE
                ORDER BY indexed_date DESC
            """)
            
            rows = cursor.fetchall()
            conn.close()
            
            return [
                {
                    "file_name": row[0],
                    "file_size": row[1],
                    "file_type": row[2],
                    "chunk_count": row[3],
                    "processing_time": row[4],
                    "indexed_date": row[5],
                    "extraction_success": row[6]
                }
                for row in rows
            ]
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _get_docs_sync)
    
    async def delete_document(self, file_path: str) -> Dict[str, Any]:
        """Delete document from vector store and metadata database."""
        if not self.initialized:
            raise RuntimeError("RAG engine not initialized")
        
        file_path = Path(file_path)
        
        try:
            # Get content hash for this file
            def _get_hash_sync():
                conn = sqlite3.connect(str(self.metadata_db_path))
                cursor = conn.cursor()
                
                cursor.execute("SELECT content_hash FROM documents WHERE file_path = ?", (str(file_path),))
                result = cursor.fetchone()
                conn.close()
                return result[0] if result else None
            
            loop = asyncio.get_event_loop()
            content_hash = await loop.run_in_executor(None, _get_hash_sync)
            
            if not content_hash:
                return {
                    "success": False,
                    "error": "Document not found in database",
                    "file_path": str(file_path)
                }
            
            # Delete from ChromaDB
            self.collection.delete(
                where={"document_id": content_hash}
            )
            
            # Delete from metadata database
            def _delete_sync():
                conn = sqlite3.connect(str(self.metadata_db_path))
                cursor = conn.cursor()
                
                cursor.execute("DELETE FROM documents WHERE file_path = ?", (str(file_path),))
                conn.commit()
                conn.close()
            
            await loop.run_in_executor(None, _delete_sync)
            
            logger.info("Document deleted successfully", file_path=str(file_path))
            
            return {
                "success": True,
                "file_path": str(file_path),
                "content_hash": content_hash
            }
            
        except Exception as e:
            logger.error("Failed to delete document", file_path=str(file_path), error=str(e))
            return {
                "success": False,
                "error": str(e),
                "file_path": str(file_path)
            }
    
    async def get_stats(self) -> Dict[str, Any]:
        """Get RAG engine statistics."""
        if not self.initialized:
            raise RuntimeError("RAG engine not initialized")
        
        try:
            # Get collection stats
            collection_count = self.collection.count()
            
            # Get metadata stats
            def _get_stats_sync():
                conn = sqlite3.connect(str(self.metadata_db_path))
                cursor = conn.cursor()
                
                cursor.execute("SELECT COUNT(*) FROM documents WHERE extraction_success = TRUE")
                doc_count = cursor.fetchone()[0]
                
                cursor.execute("SELECT SUM(chunk_count) FROM documents WHERE extraction_success = TRUE")
                total_chunks = cursor.fetchone()[0] or 0
                
                cursor.execute("SELECT SUM(file_size) FROM documents WHERE extraction_success = TRUE")
                total_size = cursor.fetchone()[0] or 0
                
                cursor.execute("SELECT AVG(processing_time) FROM documents WHERE extraction_success = TRUE")
                avg_processing_time = cursor.fetchone()[0] or 0
                
                conn.close()
                
                return doc_count, total_chunks, total_size, avg_processing_time
            
            loop = asyncio.get_event_loop()
            doc_count, total_chunks, total_size, avg_processing_time = await loop.run_in_executor(None, _get_stats_sync)
            
            return {
                "vector_count": collection_count,
                "document_count": doc_count,
                "total_chunks": total_chunks,
                "total_size_bytes": total_size,
                "total_size_mb": round(total_size / (1024 * 1024), 2),
                "avg_processing_time": round(avg_processing_time, 2),
                "hnsw_config": self.hnsw_config,
                "db_path": str(self.db_path),
                "initialized": self.initialized
            }
            
        except Exception as e:
            logger.error("Failed to get stats", error=str(e))
            return {
                "error": str(e),
                "initialized": self.initialized
            }
