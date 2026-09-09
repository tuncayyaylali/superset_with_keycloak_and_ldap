import logging
import jwt
from flask_appbuilder.security.views import AuthOAuthView
from superset.security import SupersetSecurityManager

logger = logging.getLogger(__name__)

# Monkey-patch Authlib OpenIDMixin.parse_id_token to accept both frontend (localhost:8080)
# and cluster-internal (keycloak.superset-bi.svc.cluster.local:8080) Keycloak issuer claims.
try:
    from authlib.integrations.base_client.sync_openid import OpenIDMixin

    orig_parse_id_token = OpenIDMixin.parse_id_token

    def permissive_parse_id_token(self, token, nonce, claims_options=None, leeway=120):
        if claims_options is None:
            claims_options = {
                "iss": {
                    "values": [
                        "http://localhost:8080/realms/analytics-realm",
                        "http://127.0.0.1:8080/realms/analytics-realm",
                        "http://keycloak.superset-bi.svc.cluster.local:8080/realms/analytics-realm",
                    ]
                }
            }
        return orig_parse_id_token(
            self, token, nonce, claims_options=claims_options, leeway=leeway
        )

    OpenIDMixin.parse_id_token = permissive_parse_id_token
    logger.info(
        "[CustomSsoSecurityManager] Successfully patched OpenIDMixin.parse_id_token for multi-origin OIDC issuer validation."
    )
except Exception as e:
    logger.warning(f"[CustomSsoSecurityManager] Could not patch OpenIDMixin: {e}")

# Group to Role Mapping Specification (per AGENTS.md)
# bi-admins          -> Admin
# bi-analysts        -> Alpha (SQL Lab access, dataset creation)
# bi-finance-viewers -> Gamma + Finance_Viewers (No SQL Lab, restricted views)
# bi-sales-viewers   -> Gamma + Sales_Viewers   (No SQL Lab, restricted views)
GROUP_ROLE_MAPPING = {
    "bi-admins": ["Admin"],
    "bi-analysts": ["Alpha"],
    "bi-finance-viewers": ["Gamma", "Finance_Viewers"],
    "bi-sales-viewers": ["Gamma", "Sales_Viewers"]
}


class CustomSsoSecurityManager(SupersetSecurityManager):
    """
    Custom Security Manager extending SupersetSecurityManager to implement:
    1. Keycloak OpenID Connect token decoding and claims extraction.
    2. Dynamic role synchronization on user login based on LDAP groups.
    3. Strict enforcement of least-privilege security policies for viewers.
    """

    def oauth_user_info(self, provider, response=None):
        """
        Extract user information and LDAP group memberships from Keycloak OIDC tokens.
        """
        if provider == "keycloak":
            token = response.get("access_token") if response else None
            id_token = response.get("id_token") if response else None

            claims = {}
            # Prefer id_token or fallback to access_token
            for raw_token in [id_token, token]:
                if raw_token:
                    try:
                        decoded = jwt.decode(
                            raw_token,
                            options={"verify_signature": False},
                            algorithms=["RS256"]
                        )
                        claims.update(decoded)
                    except Exception as e:
                        logger.warning(f"Error decoding JWT token from {provider}: {e}")

            username = (
                claims.get("preferred_username")
                or claims.get("sub")
                or claims.get("email")
            )
            email = claims.get("email") or f"{username}@example.org"
            first_name = claims.get("given_name") or username
            last_name = claims.get("family_name") or "User"
            groups = claims.get("groups", [])

            # Handle possible string representation of groups
            if isinstance(groups, str):
                groups = [groups]

            logger.info(
                f"[CustomSsoSecurityManager] User: {username}, Email: {email}, Groups: {groups}"
            )

            return {
                "username": username,
                "email": email,
                "first_name": first_name,
                "last_name": last_name,
                "groups": groups,
            }

        return super().oauth_user_info(provider, response)

    def auth_user_oauth(self, userinfo):
        """
        Authenticate user and synchronize roles dynamically based on LDAP groups.
        """
        user = super().auth_user_oauth(userinfo)
        if not user:
            return None

        groups = userinfo.get("groups", [])
        roles_to_assign = set()

        for group in groups:
            mapped_roles = GROUP_ROLE_MAPPING.get(group)
            if mapped_roles:
                for role_name in mapped_roles:
                    roles_to_assign.add(role_name)

        # Fallback to default registration role if no mapped groups found
        if not roles_to_assign:
            default_role = self.auth_user_registration_role or "Public"
            roles_to_assign.add(default_role)

        # Security First rule (AGENTS.md):
        # Users mapped to Gamma role must never be granted permissions containing can_sqllab or can_write.
        is_viewer = any("viewers" in g for g in groups)
        is_privileged = any(g in ["bi-admins", "bi-analysts"] for g in groups)

        if is_viewer and not is_privileged:
            roles_to_assign.discard("Admin")
            roles_to_assign.discard("Alpha")

        # Resolve role objects from Superset metadata DB
        user_roles = []
        for role_name in sorted(roles_to_assign):
            role = self.find_role(role_name)
            if not role:
                logger.info(f"Role '{role_name}' not found. Creating custom role in database.")
                role = self.add_role(role_name)
            if role:
                user_roles.append(role)

        # Update and persist user roles
        user.roles = user_roles
        self.get_session.commit()

        logger.info(
            f"[CustomSsoSecurityManager] Updated roles for '{user.username}': {[r.name for r in user_roles]}"
        )

        return user

