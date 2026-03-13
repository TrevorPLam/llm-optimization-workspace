# Test Document for RAG System

This is a test document to verify the document ingestion and processing pipeline.

## Features Tested

1. **Text Extraction**: This markdown content should be extracted properly
2. **Chunking**: The document should be split into semantic chunks
3. **Embedding**: Chunks should be converted to vector embeddings
4. **Storage**: Chunks should be stored in ChromaDB with metadata

## Technical Details

The RAG system uses:
- ChromaDB 1.5.x for vector storage
- Recursive character text splitting with 512 token chunks
- Cosine similarity for semantic search
- SHA-256 hashing for deduplication

## Expected Behavior

When uploaded, this document should:
- Pass security scanning (no threats)
- Be processed successfully
- Generate multiple chunks
- Be searchable via the API

This concludes the test document.
