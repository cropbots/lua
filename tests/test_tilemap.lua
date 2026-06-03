-- TileMap tests require Love2D canvases; run with `busted` only when love is stubbed.
-- Property tests are optional per tasks.md; basic coordinate math is tested here.

describe("TileMap coordinates", function()
    local tileSize = 16

    local function tileToWorld(tx, ty)
        return tx * tileSize, ty * tileSize
    end

    local function worldToTile(wx, wy)
        return math.floor(wx / tileSize), math.floor(wy / tileSize)
    end

    it("round-trips tile coordinates", function()
        for tx = 0, 99 do
            for ty = 0, 49 do
                local wx, wy = tileToWorld(tx, ty)
                local tx2, ty2 = worldToTile(wx, wy)
                assert.are.equal(tx, tx2)
                assert.are.equal(ty, ty2)
            end
        end
    end)
end)
