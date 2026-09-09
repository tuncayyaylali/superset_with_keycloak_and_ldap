# ==============================================================================
# Production Apache Superset Container with Keycloak OIDC & LDAP Dependencies
# ==============================================================================
FROM apache/superset:3.1.1

USER root

# Install dependencies for OAuth2 / OIDC JWT token processing and PostgreSQL
RUN pip install --no-cache-dir \
    authlib==1.3.0 \
    pyjwt==2.8.0 \
    psycopg2-binary==2.9.9

# Copy custom security manager and configuration into pythonpath
COPY superset/security/custom_sso_security_manager.py /app/pythonpath/custom_sso_security_manager.py
COPY superset/config/superset_config.py /app/pythonpath/superset_config.py

USER superset

