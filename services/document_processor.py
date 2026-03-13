"""
Document processing service for LLM Optimization Workspace.

This service provides text extraction from multiple document formats
with security scanning, content deduplication, and metadata extraction.
"""

import asyncio
import hashlib
import logging
import os
import subprocess
import tempfile
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple, Union
import zipfile

import structlog
from pydantic import BaseModel, Field

# Document processing libraries
try:
    import fitz  # PyMuPDF
    PYMUPDF_AVAILABLE = True
except ImportError:
    PYMUPDF_AVAILABLE = False

try:
    from docx import Document
    DOCX_AVAILABLE = True
except ImportError:
    DOCX_AVAILABLE = False


logger = structlog.get_logger(__name__)


class DocumentMetadata(BaseModel):
    """Metadata for processed documents."""
    file_path: str = Field(..., description="Original file path")
    file_name: str = Field(..., description="Original file name")
    file_size: int = Field(..., description="File size in bytes")
    file_type: str = Field(..., description="File type/extension")
    content_hash: str = Field(..., description="SHA-256 hash of content")
    extraction_method: str = Field(..., description="Method used for extraction")
    page_count: Optional[int] = Field(None, description="Number of pages (if applicable)")
    chunk_count: Optional[int] = Field(None, description="Number of chunks generated")
    processing_time: Optional[float] = Field(None, description="Processing time in seconds")
    virus_scan_result: Optional[str] = Field(None, description="Virus scan result")
    extraction_success: bool = Field(..., description="Whether extraction was successful")
    error_message: Optional[str] = Field(None, description="Error message if failed")


class ExtractedContent(BaseModel):
    """Extracted content from a document."""
    text: str = Field(..., description="Extracted text content")
    metadata: DocumentMetadata = Field(..., description="Document metadata")
    sections: Optional[List[Dict[str, Any]]] = Field(None, description="Document sections/structure")


class BaseExtractor(ABC):
    """Abstract base class for document extractors."""
    
    @abstractmethod
    async def extract(self, file_path: Path) -> ExtractedContent:
        """Extract text and metadata from document."""
        pass
    
    @abstractmethod
    def supported_extensions(self) -> List[str]:
        """Return list of supported file extensions."""
        pass


class PDFExtractor(BaseExtractor):
    """PDF text extractor using PyMuPDF."""
    
    def __init__(self):
        if not PYMUPDF_AVAILABLE:
            raise ImportError("PyMuPDF is required for PDF extraction")
    
    def supported_extensions(self) -> List[str]:
        return ['.pdf']
    
    async def extract(self, file_path: Path) -> ExtractedContent:
        """Extract text from PDF using PyMuPDF."""
        start_time = asyncio.get_event_loop().time()
        
        try:
            # Open PDF document
            doc = fitz.open(str(file_path))
            
            # Extract text from all pages
            text_content = []
            sections = []
            
            for page_num in range(len(doc)):
                page = doc[page_num]
                page_text = page.get_text()
                
                if page_text.strip():
                    text_content.append(page_text)
                    
                    # Extract basic structure
                    sections.append({
                        'page': page_num + 1,
                        'content': page_text.strip(),
                        'type': 'page'
                    })
            
            doc.close()
            
            full_text = '\n\n'.join(text_content)
            
            # Create metadata
            file_stat = file_path.stat()
            content_hash = self._calculate_content_hash(full_text)
            
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type='pdf',
                content_hash=content_hash,
                extraction_method='PyMuPDF',
                page_count=len(text_content),
                processing_time=asyncio.get_event_loop().time() - start_time,
                extraction_success=True
            )
            
            return ExtractedContent(
                text=full_text,
                metadata=metadata,
                sections=sections
            )
            
        except Exception as e:
            logger.error("PDF extraction failed", file_path=str(file_path), error=str(e))
            
            # Return error metadata
            file_stat = file_path.stat()
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type='pdf',
                content_hash='',
                extraction_method='PyMuPDF',
                processing_time=asyncio.get_event_loop().time() - start_time,
                extraction_success=False,
                error_message=str(e)
            )
            
            return ExtractedContent(text='', metadata=metadata)
    
    def _calculate_content_hash(self, content: str) -> str:
        """Calculate SHA-256 hash of content."""
        return hashlib.sha256(content.encode('utf-8')).hexdigest()


class DOCXExtractor(BaseExtractor):
    """DOCX text extractor using python-docx."""
    
    def __init__(self):
        if not DOCX_AVAILABLE:
            raise ImportError("python-docx is required for DOCX extraction")
    
    def supported_extensions(self) -> List[str]:
        return ['.docx']
    
    async def extract(self, file_path: Path) -> ExtractedContent:
        """Extract text from DOCX using python-docx."""
        start_time = asyncio.get_event_loop().time()
        
        try:
            # Run in thread to avoid blocking
            def _extract_sync():
                doc = Document(str(file_path))
                text_content = []
                sections = []
                
                for paragraph in doc.paragraphs:
                    if paragraph.text.strip():
                        text_content.append(paragraph.text.strip())
                        sections.append({
                            'type': 'paragraph',
                            'content': paragraph.text.strip(),
                            'style': paragraph.style.name if paragraph.style else 'Normal'
                        })
                
                return '\n\n'.join(text_content), sections
            
            # Execute in thread pool
            loop = asyncio.get_event_loop()
            full_text, sections = await loop.run_in_executor(None, _extract_sync)
            
            # Create metadata
            file_stat = file_path.stat()
            content_hash = self._calculate_content_hash(full_text)
            
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type='docx',
                content_hash=content_hash,
                extraction_method='python-docx',
                page_count=len(text_content) if full_text else 0,
                processing_time=asyncio.get_event_loop().time() - start_time,
                extraction_success=True
            )
            
            return ExtractedContent(
                text=full_text,
                metadata=metadata,
                sections=sections
            )
            
        except Exception as e:
            logger.error("DOCX extraction failed", file_path=str(file_path), error=str(e))
            
            # Return error metadata
            file_stat = file_path.stat()
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type='docx',
                content_hash='',
                extraction_method='python-docx',
                processing_time=asyncio.get_event_loop().time() - start_time,
                extraction_success=False,
                error_message=str(e)
            )
            
            return ExtractedContent(text='', metadata=metadata)
    
    def _calculate_content_hash(self, content: str) -> str:
        """Calculate SHA-256 hash of content."""
        return hashlib.sha256(content.encode('utf-8')).hexdigest()


class TextExtractor(BaseExtractor):
    """Plain text and markdown extractor."""
    
    def supported_extensions(self) -> List[str]:
        return ['.txt', '.md', '.rst', '.py', '.js', '.html', '.css', '.json', '.xml', '.yaml', '.yml']
    
    async def extract(self, file_path: Path) -> ExtractedContent:
        """Extract text from plain text files."""
        start_time = asyncio.get_event_loop().time()
        
        try:
            # Run file reading in thread to avoid blocking
            def _read_sync():
                with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                    return f.read()
            
            loop = asyncio.get_event_loop()
            full_text = await loop.run_in_executor(None, _read_sync)
            
            # Basic structure detection for code files
            sections = []
            if file_path.suffix in ['.py', '.js']:
                lines = full_text.split('\n')
                for i, line in enumerate(lines):
                    if line.strip() and not line.strip().startswith('#'):
                        sections.append({
                            'type': 'code_line',
                            'content': line.strip(),
                            'line_number': i + 1
                        })
            else:
                # Split into paragraphs for text files
                paragraphs = [p.strip() for p in full_text.split('\n\n') if p.strip()]
                for i, paragraph in enumerate(paragraphs):
                    sections.append({
                        'type': 'paragraph',
                        'content': paragraph,
                        'paragraph_number': i + 1
                    })
            
            # Create metadata
            file_stat = file_path.stat()
            content_hash = self._calculate_content_hash(full_text)
            
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type=file_path.suffix[1:],  # Remove dot
                content_hash=content_hash,
                extraction_method='text_reader',
                page_count=len(sections) if sections else 0,
                processing_time=asyncio.get_event_loop().time() - start_time,
                extraction_success=True
            )
            
            return ExtractedContent(
                text=full_text,
                metadata=metadata,
                sections=sections
            )
            
        except Exception as e:
            logger.error("Text extraction failed", file_path=str(file_path), error=str(e))
            
            # Return error metadata
            file_stat = file_path.stat()
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type=file_path.suffix[1:],
                content_hash='',
                extraction_method='text_reader',
                processing_time=asyncio.get_event_loop().time() - start_time,
                extraction_success=False,
                error_message=str(e)
            )
            
            return ExtractedContent(text='', metadata=metadata)
    
    def _calculate_content_hash(self, content: str) -> str:
        """Calculate SHA-256 hash of content."""
        return hashlib.sha256(content.encode('utf-8')).hexdigest()


class SecurityScanner:
    """Security scanning for uploaded files."""
    
    def __init__(self):
        self.max_file_size = 50 * 1024 * 1024  # 50MB
        self.max_nesting_depth = 5  # Max zip archive nesting
    
    async def scan_file(self, file_path: Path) -> Tuple[bool, str]:
        """
        Scan file for security threats.
        
        Returns:
            Tuple of (is_safe, scan_result_message)
        """
        try:
            # Check file size
            file_size = file_path.stat().st_size
            if file_size > self.max_file_size:
                return False, f"File too large: {file_size / (1024*1024):.1f}MB (max: 50MB)"
            
            # Check for zip bombs
            if file_path.suffix.lower() == '.zip':
                is_safe, message = await self._check_zip_bomb(file_path)
                if not is_safe:
                    return False, message
            
            # Virus scan with Windows Defender
            is_safe, message = await self._virus_scan(file_path)
            return is_safe, message
            
        except Exception as e:
            logger.error("Security scan failed", file_path=str(file_path), error=str(e))
            return False, f"Security scan error: {str(e)}"
    
    async def _check_zip_bomb(self, file_path: Path) -> Tuple[bool, str]:
        """Check for zip bomb (nested archives)."""
        try:
            def _check_zip_sync():
                with zipfile.ZipFile(file_path, 'r') as zip_file:
                    return self._count_nesting_depth(zip_file)
            
            loop = asyncio.get_event_loop()
            nesting_depth = await loop.run_in_executor(None, _check_zip_sync)
            
            if nesting_depth > self.max_nesting_depth:
                return False, f"Zip bomb detected: nesting depth {nesting_depth} (max: {self.max_nesting_depth})"
            
            return True, "Zip file safe"
            
        except Exception as e:
            return False, f"Zip bomb check failed: {str(e)}"
    
    def _count_nesting_depth(self, zip_file: zipfile.ZipFile, current_depth: int = 0) -> int:
        """Recursively count nesting depth in zip file."""
        max_depth = current_depth
        
        for file_info in zip_file.filelist:
            if file_info.filename.lower().endswith('.zip'):
                # Extract nested zip to temp file and check it
                try:
                    with tempfile.NamedTemporaryFile(suffix='.zip', delete=False) as temp_file:
                        temp_file.write(zip_file.read(file_info.filename))
                        temp_file.flush()
                        
                        with zipfile.ZipFile(temp_file.name, 'r') as nested_zip:
                            nested_depth = self._count_nesting_depth(nested_zip, current_depth + 1)
                            max_depth = max(max_depth, nested_depth)
                        
                        os.unlink(temp_file.name)
                except:
                    # If we can't process the nested zip, count it as depth
                    max_depth = max(max_depth, current_depth + 1)
        
        return max_depth
    
    async def _virus_scan(self, file_path: Path) -> Tuple[bool, str]:
        """Scan file with Windows Defender."""
        try:
            # Use Windows Defender CLI
            cmd = [
                'MpCmdRun.exe',
                '-Scan',
                '-ScanType',
                'CustomScan',
                '-File',
                str(file_path),
                '-DisableRemediation'  # Don't delete files, just report
            ]
            
            # Run scan in subprocess
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await process.communicate()
            
            # Check return code
            if process.returncode == 0:
                return True, "No threats detected"
            else:
                # Check for threat indicators in output
                output = stdout.decode() + stderr.decode()
                if any(keyword in output.lower() for keyword in ['threat', 'virus', 'malware']):
                    return False, "Threat detected by Windows Defender"
                else:
                    # Non-zero return code but no explicit threat - might be error
                    return True, f"Scan completed with return code {process.returncode}"
            
        except FileNotFoundError:
            # Windows Defender not available
            logger.warning("Windows Defender not available, skipping virus scan")
            return True, "Virus scan skipped (Windows Defender not available)"
        except Exception as e:
            logger.error("Virus scan failed", file_path=str(file_path), error=str(e))
            return False, f"Virus scan error: {str(e)}"


class DocumentProcessor:
    """Main document processing service."""
    
    def __init__(self):
        self.extractors: Dict[str, BaseExtractor] = {}
        self.security_scanner = SecurityScanner()
        self._initialize_extractors()
    
    def _initialize_extractors(self):
        """Initialize available extractors."""
        # Register extractors based on library availability
        if PYMUPDF_AVAILABLE:
            pdf_extractor = PDFExtractor()
            for ext in pdf_extractor.supported_extensions():
                self.extractors[ext] = pdf_extractor
        
        if DOCX_AVAILABLE:
            docx_extractor = DOCXExtractor()
            for ext in docx_extractor.supported_extensions():
                self.extractors[ext] = docx_extractor
        
        # Always available text extractor
        text_extractor = TextExtractor()
        for ext in text_extractor.supported_extensions():
            self.extractors[ext] = text_extractor
        
        logger.info("Document processors initialized", 
                   extractors=list(self.extractors.keys()))
    
    def get_supported_extensions(self) -> List[str]:
        """Get list of supported file extensions."""
        return list(self.extractors.keys())
    
    async def process_document(self, file_path: Union[str, Path]) -> ExtractedContent:
        """
        Process a document through security scan and extraction.
        
        Args:
            file_path: Path to the document file
            
        Returns:
            ExtractedContent with text and metadata
        """
        file_path = Path(file_path)
        
        logger.info("Processing document", file_path=str(file_path))
        
        # Security scan
        is_safe, scan_message = await self.security_scanner.scan_file(file_path)
        
        if not is_safe:
            logger.warning("Document failed security scan", 
                          file_path=str(file_path), reason=scan_message)
            
            # Return error metadata
            file_stat = file_path.stat()
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type=file_path.suffix[1:] if file_path.suffix else 'unknown',
                content_hash='',
                extraction_method='security_failed',
                virus_scan_result=scan_message,
                extraction_success=False,
                error_message=f"Security scan failed: {scan_message}"
            )
            
            return ExtractedContent(text='', metadata=metadata)
        
        # Check if we have an extractor for this file type
        file_ext = file_path.suffix.lower()
        
        if file_ext not in self.extractors:
            logger.warning("No extractor available for file type", 
                          file_path=str(file_path), file_type=file_ext)
            
            # Return error metadata
            file_stat = file_path.stat()
            metadata = DocumentMetadata(
                file_path=str(file_path),
                file_name=file_path.name,
                file_size=file_stat.st_size,
                file_type=file_ext[1:] if file_ext else 'unknown',
                content_hash='',
                extraction_method='not_supported',
                virus_scan_result=scan_message,
                extraction_success=False,
                error_message=f"Unsupported file type: {file_ext}"
            )
            
            return ExtractedContent(text='', metadata=metadata)
        
        # Extract content
        extractor = self.extractors[file_ext]
        extracted_content = await extractor.extract(file_path)
        
        # Add virus scan result to metadata
        extracted_content.metadata.virus_scan_result = scan_message
        
        logger.info("Document processing completed", 
                   file_path=str(file_path),
                   success=extracted_content.metadata.extraction_success,
                   text_length=len(extracted_content.text),
                   processing_time=extracted_content.metadata.processing_time)
        
        return extracted_content
    
    async def batch_process(self, file_paths: List[Union[str, Path]]) -> List[ExtractedContent]:
        """
        Process multiple documents in parallel.
        
        Args:
            file_paths: List of file paths to process
            
        Returns:
            List of ExtractedContent objects
        """
        logger.info("Starting batch document processing", count=len(file_paths))
        
        # Process files concurrently with limited concurrency
        semaphore = asyncio.Semaphore(4)  # Limit to 4 concurrent processes
        
        async def process_with_semaphore(file_path):
            async with semaphore:
                return await self.process_document(file_path)
        
        tasks = [process_with_semaphore(fp) for fp in file_paths]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Convert exceptions to error results
        processed_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error("Document processing failed", 
                           file_path=str(file_paths[i]), error=str(result))
                
                # Create error result
                file_path = Path(file_paths[i])
                file_stat = file_path.stat()
                metadata = DocumentMetadata(
                    file_path=str(file_path),
                    file_name=file_path.name,
                    file_size=file_stat.st_size,
                    file_type=file_path.suffix[1:] if file_path.suffix else 'unknown',
                    content_hash='',
                    extraction_method='batch_error',
                    extraction_success=False,
                    error_message=str(result)
                )
                processed_results.append(ExtractedContent(text='', metadata=metadata))
            else:
                processed_results.append(result)
        
        successful_count = sum(1 for r in processed_results if r.metadata.extraction_success)
        logger.info("Batch processing completed", 
                   total=len(file_paths),
                   successful=successful_count,
                   failed=len(file_paths) - successful_count)
        
        return processed_results


# Global instance
document_processor = DocumentProcessor()
