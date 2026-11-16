-- =============================================================================
-- 20261116000001_drop_dead_invitation_policy.sql
-- S-30: politica muerta en family_invitations.
--
-- "Inviters can view their own invitations" nunca se evaluaba: 0005 no da
-- ningun grant de SELECT sobre family_invitations a authenticated (la tabla
-- es de acceso exclusivo via SECURITY DEFINER), y la app no consulta la
-- tabla directamente (0 usos en lib/). Politica inofensiva pero engañosa:
-- podria hacer pensar que existe acceso directo a la tabla.
--
-- DROP sin efecto observable alguno. La baseline 0002 se conserva fiel; la
-- eliminacion vive aqui, como en el resto de correcciones sobre el volcado.
--
-- Solo creacion de archivo: NO aplicar a produccion sin revision.
-- =============================================================================

drop policy if exists "Inviters can view their own invitations" on public.family_invitations;
