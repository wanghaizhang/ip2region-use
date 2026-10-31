-- ============================================================================
-- config.lua : central configuration for the image-service Lua modules
-- ============================================================================
-- All tunables live here so the nginx config and the API layer share one source
-- of truth. Values here are defaults; production deployments should override the
-- security-sensitive ones (secret_key, allowed_sources) via environment
-- variables read at startup (see security.lua / load_env).
-- ----------------------------------------------------------------------------

local M = {}

-- ---- network / upstream ---------------------------------------------------
-- imgproxy is reached on the internal Docker network. When imgproxy runs in a
-- separate container, set imgproxy_host to the container/service name and add
-- the same network to the OpenResty container. When imgproxy runs on localhost
-- (e.g. --net=host), keep imgproxy_host = 127.0.0.1.
M.imgproxy_host = os.getenv("IMGPROXY_HOST") or "112.126.80.252"
M.imgproxy_port = tonumber(os.getenv("IMGPROXY_PORT") or "35096")

-- Internal location that serves decoded base64/upload temp files so that
-- imgproxy can fetch the raw source. Must be `internal` (not publicly routable)
-- and reachable from the imgproxy network.
M.internal_base = "/__imgsrv_tmp"

-- ---- limits (MiB unless noted) --------------------------------------------
M.max_request_body_bytes = 20 * 1024 * 1024   -- ngx.var.request_body cap
M.max_base64_input_bytes = 20 * 1024 * 1024   -- decoded source size cap
M.max_pixels             = 20 * 1024 * 1024   -- 20 MP source ceiling
M.max_output_dimension   = 2560               -- longest output edge (px)
M.default_quality        = 80
M.process_timeout_ms     = 30000              -- socket read timeout to imgproxy

-- ---- source control -------------------------------------------------------
-- Whitelist of allowed source hostnames (without scheme). Empty = disabled
-- whitelist (any HTTPS source allowed). Used only in "trusted-domain" mode.
M.allowed_sources = {}   -- e.g. {"static.example.com","cdn.yoursite.com"}

-- ---- signing (imgproxy) ---------------------------------------------------
-- Shared secret between this API and imgproxy. imgproxy signs the processed
-- path with HMAC-SHA256; the signature is embedded in the internal URL so that
-- callers cannot tamper with width/height/format/quality. Stored server-side
-- only, never returned to clients.
M.secret_key = os.getenv("IMGPROXY_SECRET_KEY") or "be12eaea1dce00a71da2145ae8002145291d4cd4c038f52177fea1b8e98c3398"
M.secret_salt = os.getenv("IMGPROXY_SECRET_SALT") or "a5d933a0edf681c43bebda1d21f3096da067ecb8dbbe26ba36feb88c8937b531"

-- ---- temp files -----------------------------------------------------------
-- Temp files live outside the public root and use random tokens. They are
-- deleted after each request and cleaned by a background timer.
M.tmp_dir = "tmp/imgsrv"

-- ---- rate limiting (per client IP) ----------------------------------------
M.rate_limit_rps   = 5     -- requests / second
M.rate_limit_burst = 20    -- leaky-bucket burst

-- ---- CORS (optional) ------------------------------------------------------
M.cors_allow_origin = "*"

return M
