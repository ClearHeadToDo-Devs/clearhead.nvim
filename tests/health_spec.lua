local assert = require("luassert")
local grammar_drift = require("clearhead.health")._testing["grammar-drift"]

local CLI = "clearhead 0.3.1 (specification v0.2.0, grammar v%s)"

describe("health compares the parser grammar with the CLI's", function()
	it("reports ok when both name the same release", function()
		local report = grammar_drift("0.10.0", CLI:format("0.10.0"))
		assert.are.equal("ok", report.level)
		assert.are.equal("clearhead CLI grammar v0.10.0", report.msg)
	end)

	it("warns that the parser is behind, with the parser fix", function()
		local report = grammar_drift("0.9.2", CLI:format("0.10.0"))
		assert.are.equal("warn", report.level)
		assert.are.equal("parser grammar v0.9.2 is behind the clearhead CLI's v0.10.0", report.msg)
		assert.truthy(report.advice:find(":TSUpdate actions", 1, true))
	end)

	it("warns that the CLI is behind, with the CLI fix", function()
		local report = grammar_drift("0.11.0", CLI:format("0.10.0"))
		assert.are.equal("warn", report.level)
		assert.are.equal("clearhead CLI grammar v0.10.0 is behind the parser's v0.11.0", report.msg)
		assert.are.equal("Upgrade clearhead", report.advice)
	end)

	it("informs, not errors, when an older CLI does not report a grammar", function()
		local report = grammar_drift("0.10.0", "clearhead 0.3.1 (specification v0.2.0)")
		assert.are.equal("info", report.level)
	end)

	it("reports nothing when either side is unknown", function()
		assert.is_nil(grammar_drift(nil, CLI:format("0.10.0")))
		assert.is_nil(grammar_drift("0.10.0", nil))
	end)
end)
