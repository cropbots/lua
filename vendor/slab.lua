-- Redirect require("vendor.slab") to require("vendor.slab.init")
-- This avoids directory resolution bugs in some packaging tools and love.js.
return require("vendor.slab.init")
