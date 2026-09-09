import os
import logging
from flask_appbuilder.security.manager import AUTH_OAUTH
from custom_sso_security_manager import CustomSsoSecurityManager

logger = logging.getLogger(__name__)

# ------------------------------------------------------------------------------
# Secret Key & Application Configuration
# ------------------------------------------------------------------------------
SECRET_KEY = os.environ.get(
    "SUPERSET_SECRET_KEY", "superset-secret-key-change-in-production-12345"
)
SUPERSET_WEBSERVER_TIMEOUT = 120
ROW_LIMIT = 5000
ENABLE_PROXY_FIX = True

# ------------------------------------------------------------------------------
# Database Connection (Superset Application Metadata)
# ------------------------------------------------------------------------------
DB_USER = os.environ.get("POSTGRES_USER", "superset")
DB_PASS = os.environ.get("POSTGRES_PASSWORD", "supersetpassword")
DB_HOST = os.environ.get("POSTGRES_HOST", "superset-db.superset-bi.svc.cluster.local")
DB_PORT = os.environ.get("POSTGRES_PORT", "5432")
DB_NAME = os.environ.get("POSTGRES_DB", "superset")

SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

# ------------------------------------------------------------------------------
# Caching & Celery Broker (Redis)
# ------------------------------------------------------------------------------
REDIS_HOST = os.environ.get("REDIS_HOST", "superset-redis.superset-bi.svc.cluster.local")
REDIS_PORT = os.environ.get("REDIS_PORT", "6379")

CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "superset_cache_",
    "CACHE_REDIS_URL": f"redis://{REDIS_HOST}:{REDIS_PORT}/0",
}
DATA_CACHE_CONFIG = CACHE_CONFIG
FILTER_STATE_CACHE_CONFIG = CACHE_CONFIG
EXPLORE_FORM_DATA_CACHE_CONFIG = CACHE_CONFIG


class CeleryConfig:
    broker_url = f"redis://{REDIS_HOST}:{REDIS_PORT}/1"
    imports = ("superset.sql_lab",)
    result_backend = f"redis://{REDIS_HOST}:{REDIS_PORT}/2"
    worker_prefetch_multiplier = 10
    task_acks_late = True


CELERY_CONFIG = CeleryConfig

# ------------------------------------------------------------------------------
# Architectural Feature Flags (per AGENTS.md)
# ------------------------------------------------------------------------------
FEATURE_FLAGS = {
    "DASHBOARD_RBAC": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
}

# ------------------------------------------------------------------------------
# Authentication & Custom Security Manager (Keycloak OIDC)
# ------------------------------------------------------------------------------
AUTH_TYPE = AUTH_OAUTH
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Public"
CUSTOM_SECURITY_MANAGER = CustomSsoSecurityManager
LOGOUT_REDIRECT_URL = os.environ.get(
    "LOGOUT_REDIRECT_URL",
    "http://localhost:8080/realms/analytics-realm/protocol/openid-connect/logout?post_logout_redirect_uri=http%3A%2F%2Flocalhost%3A8088%2Flogin%2F&client_id=superset",
)

# Keycloak Endpoints
KEYCLOAK_INTERNAL_BASE = os.environ.get(
    "KEYCLOAK_INTERNAL_BASE",
    "http://keycloak.superset-bi.svc.cluster.local:8080/realms/analytics-realm",
)
KEYCLOAK_FRONTEND_AUTH_URL = os.environ.get(
    "KEYCLOAK_FRONTEND_AUTH_URL",
    "http://localhost:8080/realms/analytics-realm/protocol/openid-connect/auth",
)

OAUTH_PROVIDERS = [
    {
        "name": "keycloak",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": os.environ.get("SUPERSET_OIDC_CLIENT_ID", "superset"),
            "client_secret": os.environ.get(
                "SUPERSET_OIDC_CLIENT_SECRET", "superset-client-secret-12345"
            ),
            "client_kwargs": {
                "scope": "openid email profile"
            },
            "server_metadata_url": f"{KEYCLOAK_INTERNAL_BASE}/.well-known/openid-configuration",
            "api_base_url": f"{KEYCLOAK_INTERNAL_BASE}/protocol/openid-connect/",
            "access_token_url": f"{KEYCLOAK_INTERNAL_BASE}/protocol/openid-connect/token",
            "authorize_url": KEYCLOAK_FRONTEND_AUTH_URL,
        },
    }
]

