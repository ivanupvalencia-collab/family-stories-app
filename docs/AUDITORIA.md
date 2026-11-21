# Auditoría integral — family-stories-app

**Fecha:** 2026-11-11 · **Modo original:** solo lectura (ningún archivo modificado
por la auditoría) · **Stack:** Flutter + Supabase · **Cifras en el momento del
análisis:** 13.147 LOC en `lib/` (61 archivos) · 12.341 LOC en `test/` (289
tests) · 15 scripts SQL/MD en `supabase/manual/`

Esta tabla es la **fuente de verdad del estado**. Las fichas de cada eje
conservan el texto original de la auditoría; el estado puede haber cambiado
desde entonces.

| ID | Hallazgo | Sev. | Estado |
|---|---|---|---|
| S-1 | Frontera de autorización inauditable (esquema + RLS sin versionar) | Alto | ✅ `b878d8c` · `supabase/migrations/` |
| S-2 | Dominio de deep-link inexistente → App Links no verificables | Alto | ✅ `cd5a1e0` · scheme propio `familystories://` |
| S-3 | JWT + refresh token + verificador PKCE en SharedPreferences en claro | Alto | ✅ `d2480e4` · `secure_session_storage.dart` |
| S-4 | Release firmado con el keystore de debug + `applicationId` placeholder | Medio | ⏳ **veto: no tocar el keystore** |
| S-5 | `profiles.avatar_url` es URL libre → SSRF on-device / probing de LAN | Medio | ✅ `b117d89` · allowlist en cliente + migración `20261112000001` (**no aplicada**) |
| S-6 | El logout no limpia fotos/audio/lista remota en disco | Medio | ✅ este commit · `SessionDataSweeper` (purga solo la cuenta que cierra sesión) |
| S-7 | `signOut()` sin `finally` | Medio | ✅ este commit · con reserva local; **riesgo residual:** si la revocación en servidor falló, el refresh token de este dispositivo sigue vivo hasta expirar/rotar |
| S-8 | Flag de borrado remoto activo sin el gate auditado | Medio | ✅ este commit · gate = `deletion_sql_gate_test.dart` + `lint_rls.sh` (flag ↔ RPCs versionadas) |
| S-9 | Tokens de invitación como oráculos de existencia | Medio | ↘️ Bajo (token de 256 bits, `sha256`, 7 días) |
| S-10 | `onAuthStateChange` sin `onError` en 5 puntos | Bajo | ✅ este commit |
| S-11 | `detectSessionInUri` en `true` por defecto | Bajo | ✅ `cd5a1e0` |
| S-12/13/14/15 | Content-type por nombre · sin `maxLength` · `.gitignore` sin `.env*`/keystores · PII en docs | Bajo | ✅ este commit · sniffing de magic bytes + `maxLength` 200/500/280 + CHECK `family_members.name` en `20261113000001` (sin aplicar) + nombres sanitizados en docs/tests |
| S-16 | Enlace inicial (`getInitialUri`) no capturado | Bajo | ✅ `cd5a1e0` |
| S-17 | SQL reescribe políticas ajenas con `alter policy ... format(...)` | Medio | ✅ este commit · `07` usa 3 `alter policy` explícitos + gate S-17 en `lint_rls.sh` (ambos modos) |
| S-19 | `get_story_metadata` devuelve `can_edit` siempre `true` | Medio | ✅ este commit · `can_edit` calculado (owner/recorder) en `0003` + gate S-19 en `lint_rls.sh` + test de contrato |
| S-23 | Buckets sin límite de tipo/tamaño | Medio | ✅ `b878d8c` · `0007` |
| S-24 | `TRUNCATE` para `anon`/`authenticated` | Alto | ✅ `b878d8c` · `0007` |
| S-25 | `question_text` sin límite superior | Medio | ✅ `b878d8c` · `0007` |
| S-26 | PII en comentario de una función | Bajo | ✅ `b878d8c` · `0003` |
| S-27 | `updated_at` sin trigger en 4 tablas | Bajo | ✅ este commit · triggers en `20261114000001` (**no aplicada**) + gate S-27 en `lint_rls.sh` · `stories`/`question_requests` sin columna (fuera de alcance) |
| S-28 | `get_family_invitation_preview` hace `FOR UPDATE` en una lectura | Medio | ✅ este commit · lectura sin lock en `0003` + gate S-28 en `lint_rls.sh` |
| S-29 | Bucket `avatars` sin política `DELETE` | Bajo | ✅ este commit · política own-folder en `20261115000001` (**no aplicada**) + gate S-29 |
| S-30 | Política muerta en `family_invitations` | Bajo | ✅ este commit · drop en `20261116000001` (**no aplicada**) + gate S-30 |
| S-31 | Ver `0007_hardening.sql` | — | ✅ `b878d8c` |
| A-1…A-12 | Eje de arquitectura | — | ⏳ en curso: hechos **A-2, A-3, A-4** (3/12); resto por grupos |
| C-1…C-18 | Eje de concurrencia y rendimiento | — | ✅ **completo (18/18)**: hechos **C-1…C-18** — sin vetoados en este eje |

---

## Resumen ejecutivo

| Eje | Hallazgos | Críticos/Altos | Estado |
|---|---|---|---|
| 1. Seguridad | 22 | 3 | 🟠 Riesgo alto |
| 2. Arquitectura | 20+ | 5 | 🟠 Deuda estructural |
| 3. Concurrencia/Rendim. | 17 | 5 | 🔴 Correctidad en riesgo |

**Controles que SÍ están bien (verificados):** cero secretos `service_role`/
`sb_secret` en el árbol ni en los 34 commits del historial · cero SQL crudo en
Dart (todo query-builder o `.rpc()` con nombre fijo) · cero `print`/`debugPrint`
de PII · ninguna política `using (true)` en el SQL versionado · defensas de
path-traversal rigurosas (regex por segmento + base64url) · 168 guardas `mounted`
sin uso real de `BuildContext` tras `await` · cero ciclos de importación ·
`Future.wait` bien usado en los puntos paralelizables · guards anti-double-submit
correctos en `question_screen` y `accept_invitation_screen`.

---

# EJE 1 — SEGURIDAD

## 🔴 S-1 · La frontera de autorización completa es inauditable (Alto)

El esquema base y todas las RLS de `family_members`, `stories`,
`question_requests`, `family_invitations`, `profiles` no estaban versionados —
lo declaraba el propio repo (`supabase/manual/06_...sql:1` — *"The baseline
schema is not versioned in this repository"*). El cliente escribe directamente
con solo filtros de igualdad client-side:

```dart
// family_member_service.dart:121 — el filtro eq() no enforcea nada por sí solo
.from('family_members').select(...).eq('owner_id', ownerId)

// profile_service.dart:141 — profiles es escribible por el cliente
.update({'name': name, 'avatar_key': avatarKey, 'avatar_url': avatarUrl})
.eq('id', userId)
```

Si cualquier tabla base tiene una política permisiva, hay divulgación
cross-account y no hay forma de verlo en el repositorio. Lo mismo aplica a los
buckets `avatars` y `story-audio` y a los RPC `send_question_request` /
`accept_family_invitation`.

**Fix aplicado:** volcado del esquema a `supabase/migrations/`, más
`tool/lint_rls.sh`.

## 🔴 S-2 · El dominio de deep-link no existe → App Links no verificables (Alto)

Verificado en vivo: `nslookup familystories.app` → **NXDOMAIN**.

`AndroidManifest.xml` declaraba `autoVerify="true"` sobre
`https://familystories.app/invite/`. Consecuencias: (a) `assetlinks.json` es
imposible de publicar → el enlace de invitación (un bearer token) lo puede
reclamar cualquier otra app; (b) el dominio no registrado puede ser reclamado
por un tercero; (c) los enlaces compartidos simplemente no resuelven.

**Fix aplicado:** scheme propio `familystories://invite/<token>` (opción A,
decisión del propietario). Riesgo residual aceptado: cualquier app puede
registrar el scheme, y el scheme no se linkifica en mensajeros — por eso el
campo de código acepta el enlace entero pegado.

## 🔴 S-3 · JWT + refresh token + verificador PKCE en SharedPreferences en claro (Alto)

`flutter_secure_storage` no aparecía en `pubspec.lock` (0 coincidencias) y el
manifest no desactivaba backups. La sesión completa vivía en XML/plist sin
cifrar y viajaba en device-backup.

Verificado en el código del paquete: `supabase_flutter` instala por defecto
`SharedPreferencesLocalStorage` con la clave
`sb-hwqvdrtehvixqloegilg-auth-token` y `SharedPreferencesGotrueAsyncStorage`
con la clave `supabase.auth.token-code-verifier`.

**Fix aplicado:** `lib/services/secure_session_storage.dart` con
`SecureLocalStorage` y `SecureGotrueAsyncStorage` sobre un Keystore/Keychain,
migración idempotente que solo borra el texto plano tras verificar la lectura,
y `android:allowBackup="false"`.

**Decisión de producto:** al desactivar backups, los usuarios pierden la
restauración local de datos (familias/historias) al cambiar de teléfono. Era
incompatible con no filtrar la sesión en claro.

## 🟠 Otros hallazgos de seguridad

| # | Hallazgo | Sev. | Ubicación |
|---|---|---|---|
| S-4 | Release firmado con el keystore de debug (`signingConfig = debug`) + `applicationId` placeholder `com.example.*` | Medio | `android/app/build.gradle.kts:32-38` |
| S-5 | `profiles.avatar_url` es URL libre escribible por el cliente y se descarga sin allowlist de scheme/host, con redirects activos y sin timeout → SSRF on-device / probing de LAN | Medio | `profile_avatar_image_cache.dart:183-202` ← `profile_service.dart:141` |
| S-6 | El logout no limpia fotos de familiares y stories en disco, la lista remota de familiares en prefs, ni el audio descargado en temp | Medio | grep exhaustivo de `clearOwner` |
| S-7 | `signOut()` con `await` sin `finally`: si falla la llamada al servidor se saltan el sign-out de Google y `clearCache()` | Medio | `auth_service.dart:79-88`, `profile_screen.dart:194-209` |
| S-8 | Flag `familyMemberRemoteDeletionEnabled = true` activo con el esquema sin versionar | Medio | `family_member_deletion_service.dart:5-6` |
| S-9 | Los tokens de invitación son oráculos de existencia (preview devuelve nombres) sin rate-limit visible | Medio → **Bajo** | `invitation_service.dart:39-62` |
| S-17 | SQL reescribe dinámicamente políticas ajenas con `execute format('alter policy ... or ...')` sobre `storage.objects` | Medio | ✅ `07_...sql:239-249` → 3 `alter policy` literales (Family photos require their owner / Story photo read guard / Story photo delete guard) + gate `lint_rls.sh` que prohíbe `format('alter policy` en `supabase/` |
| S-10 | `onAuthStateChange` suscrito sin `onError` en 5 puntos | Bajo | `main.dart:105`, `home_screen.dart:130`, `profile_screen.dart:65`, `answer_screen.dart:56`, `family_member_screen.dart:120` |
| S-11 | `detectSessionInUri` en default `true` | Bajo | `main.dart:32-35` |
| S-12/13/14/15 | Content-type por nombre de archivo sin sniffing · sin `maxLength` en alta de familiar/pregunta/invitación · `.gitignore` sin `.env*`/keystores · PII real (nombres) en docs del repo público | Bajo | varios |

**Limpio en este eje:** sin WebView, sin `url_launcher`, sin interpolación de
entrada en queries, path traversal imposible estructuralmente, mensajes de error
al usuario genéricos y localizados.

---

# EJE 2 — ARQUITECTURA Y ESCALABILIDAD

## 🔴 A-1 · No hay capa de dominio ni de casos de uso (Crítico)

16/16 pantallas importan servicios directamente; 7/13 widgets también, y uno
importa Supabase. Las transacciones multi-servicio viven dentro de `State`:

```dart
// family_member_screen.dart:501-535 — _delete() orquesta 5 servicios con compensación
final plan = await _deletionService.delete(...);
await _photoService.forgetPhotos(...);   await _storyPhotos.forgetPhotos(...);
await _remoteStoryService?.clearAudioCache();  await _storyStorage.deleteFamily(...);
```

Igual en `question_request_screen.dart:37-95` (upload → RPC → delete
compensatorio → attach) y `home_screen.dart:506-563`. Esta lógica debe ser
consistente entre pantallas y se re-implementa por pantalla.

**Fix:** `lib/domain/` (reglas puras) + casos de uso `DeleteFamilyMember`,
`SubmitAnswer`, `AddFamilyMember` con resultado tipado; las pantallas solo
mapean resultado → UI.

## 🔴 A-2 · Lógica de dominio dentro de widgets (Alto)

`selectHomeHero`, `requestSubtitle`, `requestDate` son funciones de dominio en
`aritoria_home_view.dart:26-76`, consumidas por un screen
(`home_screen.dart:275`). El mismo archivo hace lectura/escritura de caché en
disco y clasifica códigos de error de PostgREST (`:665-666`), duplicado en
`visible_account_avatar_service.dart:177`. Es el único import `supabase_flutter`
fuera de `services/`.

**✅ resuelto (A-2):** `lib/domain/` contiene las reglas puras —
`home_hero.dart` (`selectHomeHero`), `request_display.dart` (`requestDate`/
`requestSubtitle`), `postgrest_failure.dart` (`isPostgrestDenied`, unifica la
clasificación `42501/PGRST301` duplicada) y `app_failure.dart` (falla tipada
para los casos de uso de A-1). `aritoria_home_view.dart` queda **sin import de
`supabase_flutter`** — ya no existe ninguno fuera de `services/` y `domain/`.

## 🔴 A-3 · Acoplamiento concreto y singletons globales (Alto)

- `Supabase.instance.client` directo en 13 servicios.
- 40+ fallbacks `?? Concrete()` en la UI (p. ej. `account_avatar_view.dart:48`).
- 6 cachés `static final Expando` + 2 singletons `.shared`.
- Configuración hardcodeada: `main.dart:26-28` (URL + publishable key pegadas,
  sin `--dart-define` ni rotación).
- Sin framework de estado: solo `setState` (hasta 28 llamadas por pantalla).

**✅ resuelto (A-3):** `lib/app_graph.dart` es la raíz de composición única —
`main()` lo construye tras `Supabase.initialize` y `FamilyStoriesApp` baja de 14
params opcionales a `required AppGraph`. Los fallbacks de la capa de app
desaparecen: `HomeScreen` recibe 14 dependencias **requeridas** (2 nullable a
propósito: foto por cuenta y avatares sin cliente), el getter estático
`SupabaseVisibleAccountAvatarService.shared` se elimina (las 4 vistas reciben el
servicio del grafo; null = fallback, idéntico a `.shared` en local-only/tests),
la URL + publishable key pasan a `String.fromEnvironment` (`--dart-define`, con
los valores actuales como defaults) y el `SessionMonitor` de A-4 se comparte
desde el grafo. Los seams de test de pantallas de segundo nivel (ProfileScreen,
story/question screens) se mantienen deliberadamente: son inyección de tests,
no fallbacks de producción.

## 🔴 A-4 · Fugas de ciclo de vida en constructores de servicios (Alto)

```dart
// family_member_service.dart:53 — la suscripción no se guarda ni se cancela
_client.auth.onAuthStateChange.listen((state) { ... });
```

Cada `SupabaseFamilyMemberService()` añade un listener permanente y la interfaz
no expone `dispose()`. Mismo patrón en `story_photo_service.dart:108`,
`family_member_photo_service.dart:118`,
`persistent_story_waveform_service.dart:309`. (Solo
`visible_account_avatar_service.dart:25` lo hace bien.)

**✅ resuelto (A-4):** los 5 sitios guardan su suscripción y exponen `dispose()`
— `family_member_service` y `family_story_service` registran en un `SessionMonitor`
(una única suscripción de auth con abanico que el grafo de A-3 comparte), y las dos
cachés internas de fotos y el binding de waveforms cancelan su suscripción
directamente. Test: un servicio disposed ya no barre audio al cerrar sesión
(la fuga original lo hacía).

## 🟠 Otros hallazgos de arquitectura

| # | Hallazgo | Sev. | Evidencia |
|---|---|---|---|
| A-5 | God files: `home_screen.dart` 989 LOC / 35 campos de estado / 13 dependencias inyectadas | Alto | `home_screen.dart:71-105` |
| A-6 | Violaciones OCP: switch de strings en categorías y en acciones de menú; 9 sitios `if (service is! X) throw` + cast redundante; flag `isRemoteFamilyMember` 31 veces en 6 archivos | Alto | ver fichas |
| A-7 | Duplicación estructural: gemelos `story_photo_service` (436) vs `family_member_photo_service` (411) → ~250-280 LOC duplicados; máquina de estado de audio en `story_screen` vs `question_screen` → ~180 LOC; 3 helpers `_showMessage` + ~20 strings idénticos | Crítico/Alto | §D1, D2 |
| A-8 | Tokens de carrera reinventados en 8 archivos (~150 líneas) | Alto | `if (!mounted \|\| request != _loadRequest) return;` ×8 |
| A-9 | Estado triplicado de un mismo familiar; cada vuelta de navegación recarga todo (`_loadStories()` ×7) | Medio | `family_member_screen.dart:77,309-318` |
| A-10 | Question no enlaza hint ni icono · `familyRelationships` es `List<String>` sin tipado · añadir un servicio toca 4+ archivos y ~60 líneas | Medio | `predefined_questions.dart:4-79` |
| A-11 | Sin CI (`.github/` ausente), `flutter_lints` por defecto sin `strict-casts`/`unawaited_futures`, README intacto del template | Medio | `analysis_options.yaml` |
| A-12 | `test/widget_test.dart` = 3.467 líneas / 73 tests con 14 fakes | Bajo | `:2760-2787` |

**Positivos:** cobertura ~94% por líneas, cero ciclos, cero código muerto, cero
TODO, disciplina `mounted` excelente, inyección por constructora existente (el
patrón ya funciona — solo hay que eliminar los fallbacks).

---

# EJE 3 — CONCURRENCIA Y RENDIMIENTO

## 🔴 C-1 · Descargas concurrentes de audio escriben el mismo fichero (Crítico)

```dart
// family_story_service.dart:59-113 — sin dedup en vuelo; _audioCache se llena AL FINAL (L110)
final file = File('${cacheDirectory.path}${...}${story.id}.m4a');
await file.writeAsBytes(bytes, flush: true);   // ← dos llamadas concurrentes, misma ruta
```

Dos llamantes concurrentes pasan ambos la comprobación de caché y escriben el
mismo `.m4a` de forma intercalada → fichero truncado o corrupto. El guard de
`story_screen.dart:64,130-140` solo protege una instancia de pantalla.

**Fix:** mapa de futuros in-flight por `audioPath` (patrón ya usado en
`visible_account_avatar_service.dart:58`) + escritura a fichero temporal único
y `rename()` atómico.

## 🔴 C-2 · Read-modify-write sin serializar en SharedPreferences (Crítico)

```dart
// family_story_storage.dart:161-167 — load → mutate → save, sin mutex
final stories = await _loadAll()..add(story);
await _preferences.setStringList(_storageKey, ...);
```

`saveRecording`, `updatePhoto`, `deleteFamily` y `FamilyMemberStorage.save` se
solapan → updates perdidos a nivel de lista completa (no de clave). Irónico:
`remote_family_member_cache.dart:38-41` ya tiene el `_enqueue` correcto; solo
falta aplicarlo aquí.

## 🔴 C-3 · Cero índices en todo el repo (Alto)

`grep -ri "create index"` → 0 coincidencias. Todo se filtra por columnas FK
(`stories.family_member_id`, `question_requests.recipient_id`+`status`,
`family_members.owner_id`), y cada política RLS re-evalúa esos subqueries por
fila.

**Fix parcial:** `0006_indexes.sql` añade los 6 índices compuestos (C-3). El
casteado en políticas se resolvió en **C-4** (helpers en `0003`).

## ✅ C-4 · Las políticas de storage derrotaban el índice PK con casts `::text` (Alto) — resuelto

```sql
-- antes en 0002 (×10: 7 en family-member-photos, 3 en story-audio)
where (fm.id)::text = (storage.foldername(objects.name))[2]
```

Casteaba el uuid PK a texto → no podía usar `family_members_pkey` (seq scan);
y `storage.foldername()` se reevaluaba dos veces por política por fila.

**Fix (este commit):** los 10 `exists` inline de `0002` se sustituyen por dos
helpers nuevos en `0003`, con el patrón de `story_photo_allowed`:

- `family_member_photo_allowed(name)` → las 7 de `family-member-photos`:
  `foldername` calculado **una sola vez**, guarda regex + `exception when
  invalid_text_representation` antes del cast (una ruta malformada se deniega,
  nunca error de política) y `fm.id = <uuid>` → usa `family_members_pkey`.
- `response_audio_allowed(name, <modo>)` → las 3 de `story-audio` (modos
  `owner-read`, `responder-read`, `responder-insert`), ídem con
  `question_requests_pkey`.
- `SECURITY INVOKER` a propósito: la consulta a `family_members` /
  `question_requests` sigue evaluándose con las RLS del usuario — misma
  semántica que el `exists` inline que sustituye.
- Grants al estilo del volcado: `revoke … from public, anon` +
  `grant execute … to authenticated`.
- **Gate C-4** en `tool/lint_rls.sh` (ambos modos): prohíbe
  `id::text … = … foldername` en `migrations/`, ignorando comentarios;
  `manual/` queda exento (histórico, decisión previa).

**Verificación en Postgres local (docker `postgres:15-alpine`, NO producción):**

| Comprobación | ANTES | DESPUÉS |
|---|---|---|
| Plan de las políticas | `Seq Scan on family_members` / `question_requests` | `Index Scan using family_members_pkey` / `question_requests_pkey` (auto_explain dentro de los helpers; cero seq scan) |
| Comportamiento RLS | — | idéntico: owner ve/sube su objeto, otros no, ruta malformada denegada **sin error**, audio con `status='pending'` para subir y bloqueado al `answered` |
| Llamadas a `foldername` (barrido de fotos) | 10 | 5 (ahora exactamente 1 por evaluación de política; antes 2) |

**Salvedades:** (1) `create policy` resuelve las funciones al crearse — en una
BD nueva, `0002` exige que `0003` exista previamente; es una condición
**preexistente** (el volcado ya usaba `story_photo_allowed` de `0003`) y C-4
sigue el mismo patrón. (2) **Pendiente de prueba en vivo al aplicar a
producción** (el harness local cubre el comportamiento, no el proyecto real).

## ✅ C-5 · N+1 de RPC por cuenta en avatares (Alto) — resuelto

```dart
// antes: el RPC admite ≤100 ids y se le mandaba 1
params: {'p_account_ids': [accountId]}
```

`aritoria_home_view.dart` hacía `Future.wait(accounts.map(load))` → 50
familiares = 50 RPC donde 1 bastaba.

**Fix (este commit):**

- `VisibleAccountAvatarService.loadMany(ids)` con implementación por defecto
  que reenvía a `load` por id → los fakes de test siguen funcionando sin
  tocarlos.
- `SupabaseVisibleAccountAvatarService.loadMany`: descarta ids vacíos y los
  ya validados en caché (TTL de 5 min, mismo criterio que `load`), se une a lo
  que esté en curso (`_pending`/`_refreshes`), lee el disco en paralelo para
  los ids fríos (Home pinta lo que ya tiene mientras vuela el RPC) y manda
  **un RPC por trozo de ≤100 ids** (`_batchSize`, límite
  `cardinality(p_account_ids) <= 100` del RPC; los trozos, en paralelo).
  Misma semántica de error que `_fetch`: `42501`/`PGRST301` → nulls en caché;
  resto → reintento a 15 s y rethrow. El `_fetch` de un solo id ahora
  delega en `_fetchMany` (un único código de RPC).
- `_loadAvatars` del Home: de N `load` a **una** `loadMany` con el mismo
  try/catch (si un trozo falla, los demás ya quedaron cacheados).

**Tests (5 nuevos; los 4 previos sin cambios):** N ids → 1 RPC · 150 ids → 2
RPCs (100+50) · caché fresca no se vuelve a pedir · `loadMany` se une a un
`load` en curso (1 sola RPC) · fallo RPC → rethrow + reintento.

## ✅ C-6 · Cero paginación (Alto) — resuelto

`grep "\.range(\|\.limit(" en lib/` → 0 coincidencias. Cuatro consultas de
lista descargaban todas las filas en cada carga: stories por familiar
(`loadForFamily`, incluido su reintento `42703`), requests pendientes y
contestados por destinatario, y familiares por owner (`loadForOwner`).

**Fix (este commit):** `.range(0, 499)` al final de las 4 cadenas (tras
`.order(...)`; en `loadForFamily`, dentro del helper `query()` para cubrir
también el fallback). `postgrest` lo serializa como `offset=0&limit=500` en
la URL de la petición.

**Gate** `test/pagination_gate_test.dart` (patrón de
`deletion_sql_gate_test`): escanea `lib/**/*.dart`, extrae cada cadena
`.from('<tabla>')` hasta el `;` y exige que toda lectura (`.select(`) lleve
`.range(` / `.limit(` o una guarda de una sola fila; además, las lecturas
ordenadas deben cumplir **exactamente** `.range(0, 499)` (la política de 500
filas: cambiar el cap obliga a actualizar el gate). Incluye test negativo del
clasificador. `question_request_service_test` verifica además, en la petición
real, `offset=0` y `limit=500`.

**Trade-off aceptado:** más de 500 filas por consulta quedan fuera de la UI
(la app no tiene paginación; por el `order` existente se conservan las más
recientes). Las lecturas por RPC quedan fuera de este tope: su límite lo da
la entrada (ver C-10).

## 🟠 Otros hallazgos de concurrencia/rendimiento

| # | Hallazgo | Sev. | Ubicación |
|---|---|---|---|
| C-7 | Cero timeouts de red; HttpClient nuevo por descarga; un request colgado bloquea el avatar (**✅ resuelto**: timeouts + `followRedirects = false` desde S-5, y ahora un único `HttpClient` compartido por toda la app — avatares + storage/REST/auth vía `httpClient` en `Supabase.initialize`, con pooling de conexiones) | Medio | `profile_avatar_image_cache.dart:176-225` |
| C-8 | Doble-tap: `_isSaving` se pone tras el `await` del picker → dos filas creadas (**✅ resuelto**: guard `if (_isSaving) return` + `_isSaving = true` síncronos antes del primer `await`, con reset en el `finally`; seam `debugAddFamilyMember` fija el contrato y el test demuestra que la 2.ª creación mientras la 1.ª está abierta es no-op) | Medio | `home_screen.dart` |
| C-9 | Cola de escritura serializada y lecturas que esperan TODO el backlog (**✅ resuelto**: orden por fichero + barrera por owner en `_run`; `read`/`readEntry` solo esperan su propia clave y la barrera de su owner) | Medio | `remote_family_photo_disk_cache.dart` |
| C-10 | Bucles `await` secuenciales: chunks de RPC 100 en 100 y un `storage.remove` por objeto (**✅ resuelto**: chunks de RPC en paralelo con `Future.wait` + un remove por bucket de ≤100 rutas con cortocircuito y validación previa del plan) | Medio | `received_request_details_service.dart:29-44`, `family_member_deletion_service.dart:70-87` |
| C-11 | Cachés de disco sin techo (**✅ resuelto**: presupuesto de bytes por árbol de owner —fotos/avatares—, por directorio de sesión —audio— y por cuenta —waveforms—, con evicción por mtime tras cada escritura; los ficheros <5 s quedan protegidos y una evicción solo degrada a re-descarga) | Medio | `disk_budget.dart` + 3 clases de caché |
| C-12 | Caché de bytes con evicción por inserción, no LRU; `_byteCount` no resta la longitud previa (**✅ resuelto**: hit reordena la clave como MRU → la evicción expulsa el menos usado; `_byteCount` resta la longitud previa antes de sobrescribir; techo `maxBytes` inyectable) | Medio | `profile_avatar_image_cache.dart` |
| C-13 | Tempestad de reloads: `notifyListeners()` en cada evento de auth (**✅ resuelto**: las dos cachés notifican solo cuando la sesión visible cambia (guard de announce por `_announcedOwner`, cubre el pre-sync de getters) o al `signedOut`; `tokenRefreshed`/`userUpdated` con el mismo owner quedan silenciosos) | Medio | `visible_account_avatar_service.dart`, `profile_avatar_image_cache.dart` |
| C-14 | `ListView(children:)` no lazy en 4 sitios (**✅ resuelto**: requests y miembros → `CustomScrollView` + `SliverList.builder`; historias → `ListView.builder`; tira de miembros del home → `ListView.builder` horizontal —la `Row` materializaba todos los tiles, la única construcción eager a nivel elemento—) | Medio | 4 vistas |
| C-15 | `TextPainter..layout()` dentro de `build()` (**✅ resuelto**: `_RequestTabs` pasa a stateful con medidas memoizadas por (pendingCount, textScaler, dirección) — un rebuild plano reutiliza las medidas y solo un cambio de etiquetas re-mide) | Medio | `aritoria_requests_view.dart` |
| C-16 | Refresco de un familiar cargando la lista completa y escaneando en lineal (**✅ resuelto**: `_refreshRemoteFamilyMember` usa `loadMemberForOwner`, una fila con `.maybeSingle()`) | Medio | `family_member_screen.dart:309-318` |
| C-17 | Re-sort en cliente de resultados ya ordenados por SQL (**✅ resuelto**: borrados los dos sorts de Home; el orden lo fija `.order()` en SQL, con el order de pending ahora fijado en test de wire) | Bajo | `home_screen.dart:402-408,470` |
| C-18 | Caché de waveform compartida estática entre cuentas (**✅ resuelto**: la RAM del scope de invitado se invalida en cada transición de cuenta (`_RemoteBinding.sync`) —su disco es dato de dispositivo y se rehidrata—; `forClient` registra bindings por (cliente, disco) en vez de congelar la config de la primera llamada) | Bajo | `persistent_story_waveform_service.dart` |

**Positivos:** un único `Supabase.instance.client` compartido, `Future.wait`
correcto donde corresponde, dedup de trabajos de waveform por clave, colas
`_enqueue` en el caché remoto de familiares, y todas las disposiciones de
`TextEditingController`/`Timer`/`StreamSubscription`/`TextPainter` en widgets
correctas.

**Observación fuera de alcance (C-9):** `remote_family_member_cache.dart`
replica el antiguo patrón de cola global, pero se deja sin tocar: sus
escrituras de SharedPreferences duran sub-ms y su espera de lectura detrás de
la escritura está justificada en comentario (evita leer una clave a medio
guardar).

---

# Plan de remediación por fases

## Fase 0 — Parada de emergencia

1. ✅ C-1 dedup in-flight + `rename()` atómico en descargas de audio.
2. ✅ C-2 mutex `_enqueue` en `family_story_storage` y `family_member_storage`.
3. ✅ C-7 timeouts + `HttpClient` compartido + liberación garantizada de `_pendingBytes` → **completo** (timeouts y sin redirects desde S-5; un único `HttpClient` compartido entre avatares y todo el tráfico Supabase, con tests de pooling por puerto remoto).
4. ✅ S-7 `finally` en el sign-out (Google + cachés se ejecutan siempre) → hecho en este commit con reserva local de `signOut(scope: local)`; ver riesgo residual en la tabla de estado. También **S-10**: los errores del stream de auth (fallos de refresh) ya no pueden romper la app — módulo `auth_stream.dart` (`handleAuthStreamError` + `listenAuthSafely`) usado por los 8 servicios que se suscribían directamente y por `authUserChanges()` en `auth_service.dart`, sin tocar nunca el estado de sesión.

## Fase 1 — Frontera de seguridad

5. ✅ S-1 versionar esquema base + `pg_policies` → `supabase/migrations/`, y lint de políticas.
6. ✅ S-2 deep links (scheme propio). S-4 release keystore → **vetoado por el propietario**.
7. ✅ **S-3 sesión en Keystore/Keychain + `allowBackup="false"`.**
8. ✅ C-3 + C-4 invertir casts `::text` en las políticas de storage (10 expresiones de `0002` → helpers en `0003` · gate C-4 · verificado en Postgres local con docker).
9. ✅ **S-5 allowlist de host en `avatar_url`** (política en cliente + `CHECK` en `20261112000001`, esta sin aplicar) · ✅ **S-6 barrido de cachés en `signedOut`** (`SessionDataSweeper`: fotos, lista remota y audio; solo de la cuenta que cierra sesión; comparte las colas de escritura vía `forClient`) · ✅ **S-8 gate del flag de borrado remoto** (la confirmación "instalado" deja de ser un comentario: `test/deletion_sql_gate_test.dart` + `tool/lint_rls.sh` exigen que flag `true` ⇒ ambas RPCs con revoke/grant en `migrations/`, en ambos modos del lint). También **S-12/13/14/15**: el content-type de las fotos sale del sniffing de magic bytes (`sniffImageContentType`, sin fallback al nombre), `maxLength` 200/500/280 en alta de familiar/pregunta/código de invitación con `CHECK` de respaldo en `20261113000001` (NOT VALID, sin aplicar), `.gitignore` raíz con `.env*`/keystores, y PII (nombres reales) fuera de docs, migraciones y tests.

## Fase 2 — Escala de datos

10. ✅ C-5 lote de `get_visible_account_avatars` (≤100 ids) → `loadMany` en Home (1 RPC por lote; el `warmCached` único en Home ya existía).
11. ✅ **C-6** `.range(0, 499)` + gate `pagination_gate_test` · **C-10** chunks de RPC en paralelo + removes por bucket · **C-16** refresco con `loadMemberForOwner` · **C-17** re-sorts de Home borrados (orden fijado en SQL).

## Fase 3 — Arquitectura

12. ⏳ A-1/A-2 casos de uso fuera de pantallas + `selectHomeHero` a `domain/` + mapeo `AppFailure`.
13. ✅ **A-3** `AppGraph` único en `main()`: sin fallbacks `?? Concrete()` en la capa de app, sin `.shared`, config a `String.fromEnvironment`/`--dart-define`.
14. ⏳ A-4 `dispose()` en los servicios + suscripciones de auth centralizadas en un `SessionMonitor`.
15. ⏳ A-7/A-8 extraer `RemotePhotoStore<T>` y `AudioPlaybackController`; utilidad `AsyncValueLoader<T>`.
16. ⏳ A-5 trocear `home_screen.dart` · A-6/A-10 `Question`/`QuestionCategory`/`FamilyRelationship` tipados.

## Fase 4 — Rendimiento de UI y testabilidad

17. ✅ **C-14** listas con builder: solo se construye lo visible (requests/miembros → slivers, historias → `ListView.builder`, tira del home → horizontal) · ✅ **C-15** medidas de pestañas memoizadas, sin `TextPainter` en cada build · ✅ **C-11** presupuestos de caché en disco (techo por árbol de owner/por directorio de audio/por cuenta de waveform, evicción por mtime) · ✅ **C-12** LRU real + contabilidad exacta de `_byteCount` · ✅ **C-13** notify de auth solo cuando la sesión visible cambia. → **fase cerrada**.
18. ⏳ CI (`flutter analyze && flutter test` con lints estrictos) + README real + split de `test/widget_test.dart`.
