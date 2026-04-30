import os
import json
import uuid
import time
import base64
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum
from aws_lambda_powertools import Logger

# Import routers at the top
from routers.health import router as health_router
from routers.gemini import router as gemini_router
from routers.lexique import router as lexique_router
from routers.corpus import router as corpus_router

# 1. Initialize Logger
logger = Logger(service="Minakata")

SHOW_DOCS = os.environ.get("SHOW_API_DOCS", "true").lower() == "true"

# 2. Initialize FastAPI
app = FastAPI(
    title="Minakata API",
    description="Integrated API for Minakata Project",
    version="1.2.0",
    docs_url="/api/v1/docs" if SHOW_DOCS else None,
    redoc_url="/api/v1/redoc" if SHOW_DOCS else None,
    openapi_url="/api/v1/openapi.json" if SHOW_DOCS else None
)

# 3. CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 4. Middleware: Logging & Security
@app.middleware("http")
async def log_requests(request: Request, call_next):
    # --- [Path Normalization] ---
    # パス末尾のスラッシュの有無による不一致を防ぐ
    path = request.url.path.rstrip("/")
    
    # Skip security for docs and health
    # 💡 修正: health_routerにprefixを付けるため、ここも合わせる
    exempt_paths = [
        "/api/v1/docs", 
        "/api/v1/redoc", 
        "/api/v1/openapi.json", 
        "/api/v1/health"
    ]
    
    if any(path == p.rstrip("/") for p in exempt_paths):
        # 追跡IDだけはヘルスチェックでも生成しておく（ロギング用）
        aws_context = request.scope.get("aws.context")
        trace_id = aws_context.aws_request_id if aws_context else str(uuid.uuid4())
        request.state.minakata_traceid = trace_id
        return await call_next(request)

    # --- [Security Check] ---
    signature = request.headers.get("x-minakata-signature")
    timestamp_str = request.headers.get("x-minakata-timestamp")
    secret_key = os.environ.get("X_MINAKATA_HEADER_SECRET")

    try:
        if not signature or not timestamp_str or not secret_key:
            raise ValueError("Missing security headers")

        # A. Expiration check (30s)
        request_ts = int(timestamp_str)
        current_ts = int(time.time())
        if abs(current_ts - request_ts) > 30:
            raise ValueError("Signature expired")

        # B. Signature verification
        mod = len(signature) % 4
        padded_signature = signature + ('=' * (4 - mod) if mod else '')
        
        decoded_sig = base64.b64decode(padded_signature).decode("utf-8")
        expected_sig = f"{timestamp_str}.{secret_key}"
        
        if decoded_sig != expected_sig:
            raise ValueError("Invalid signature")

    except Exception as e:
        logger.warning(f"Security Blocked: {str(e)}")
        return JSONResponse(
            status_code=403,
            content={"detail": "Forbidden: Security verification failed."}
        )

    # --- [Tracing & Execution] ---
    start_time = time.time()
    aws_context = request.scope.get("aws.context")
    trace_id = aws_context.aws_request_id if aws_context else str(uuid.uuid4())
    request.state.minakata_traceid = trace_id

    # Body capturing for logging
    body = ""
    if request.method in ["POST", "PUT", "PATCH"]:
        try:
            body_bytes = await request.body()
            if body_bytes:
                body = body_bytes.decode("utf-8")
            
            async def receive():
                return {"type": "http.request", "body": body_bytes}
            request._receive = receive
        except Exception:
            body = "could_not_parse"

    response = await call_next(request)

    process_time_ms = round((time.time() - start_time) * 1000, 2)
    response.headers["X-Minakata-TraceID"] = trace_id

    logger.info(
        "API Request Summary",
        extra={
            "minakata_traceid": trace_id,
            "http_method": request.method,
            "http_path": request.url.path,
            "http_status": response.status_code,
            "latency_ms": process_time_ms,
        }
    )
    
    return response

# 5. Register Routers
# 💡 修正: 他のルーターと同様に prefix="/api/v1" を追加
app.include_router(health_router, prefix="/api/v1")
app.include_router(gemini_router, prefix="/api/v1")
app.include_router(lexique_router, prefix="/api/v1")
app.include_router(corpus_router, prefix="/api/v1")

# 6. Lambda Handler
@logger.inject_lambda_context(log_event=False)
def handler(event, context):
    asgi_handler = Mangum(app, lifespan="off")
    return asgi_handler(event, context)