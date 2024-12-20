-- Interpret a MathML or TeX-like AST, typeset it and add it to the output.
local b = require("packages.math.base-elements")
local syms = require("packages.math.unicode-symbols")
local mathvariants = require("packages.math.unicode-mathvariants")
local mathVariantToScriptType, scriptType = mathvariants.mathVariantToScriptType, mathvariants.scriptType

-- Shorthands for atom types, used in the `atom` command option
local atomTypeShort = {
   ord = b.atomType.ordinary,
   big = b.atomType.bigOperator,
   bin = b.atomType.binaryOperator,
   rel = b.atomType.relationalOperator,
   open = b.atomType.openingSymbol,
   close = b.atomType.closeSymbol,
   punct = b.atomType.punctuationSymbol,
   inner = b.atomType.inner,
   over = b.atomType.overSymbol,
   under = b.atomType.underSymbol,
   accent = b.atomType.accentSymbol,
   radical = b.atomType.radicalSymbol,
   vcenter = b.atomType.vcenter,
}

local ConvertMathML

local function convertChildren (tree)
   local mboxes = {}
   for _, n in ipairs(tree) do
      local box = ConvertMathML(nil, n)
      if box then
         table.insert(mboxes, box)
      end
   end
   return mboxes
end

local function convertFirstChild (tree)
   -- We need to loop until the first non-nil box is found, because
   -- we may have blank lines in the tree.
   for _, n in ipairs(tree) do
      local box = ConvertMathML(nil, n)
      if box then
         return box
      end
   end
end

-- convert MathML into mbox
function ConvertMathML (_, content)
   if content == nil or content.command == nil then
      return nil
   end
   if content.command == "math" or content.command == "mathml" then -- toplevel
      return b.stackbox("H", convertChildren(content))
   elseif content.command == "mrow" then
      return b.stackbox("H", convertChildren(content))
   elseif content.command == "mphantom" then
      -- MathML's standard mphantom corresponds to TeX's \phantom only.
      -- Let's support a special attribute "h" or "v" for TeX-like \hphantom or \vphantom.
      local special = content.options.special
      return b.phantom(convertChildren(content), special)
   elseif content.command == "mi" then
      local script = content.options.mathvariant and mathVariantToScriptType(content.options.mathvariant)
      local text = content[1]
      if type(text) ~= "string" then
         SU.error("mi command contains content which is not text")
      end
      script = script or (luautf8.len(text) == 1 and scriptType.italic or scriptType.upright)
      return b.text("identifier", {}, script, text)
   elseif content.command == "mo" then
      local script = content.options.mathvariant and mathVariantToScriptType(content.options.mathvariant)
         or scriptType.upright
      local text = content[1]
      local attributes = {}
      -- Attributes from the (default) oerator table
      if syms.symbolDefaults[text] then
         for attribute, value in pairs(syms.symbolDefaults[text]) do
            attributes[attribute] = value
         end
      end
      -- Overwrite with attributes from the element
      for attribute, value in pairs(content.options) do
         attributes[attribute] = value
      end
      if content.options.atom then
         if not atomTypeShort[content.options.atom] then
            SU.error("Unknown atom type " .. content.options.atom)
         else
            attributes.atom = atomTypeShort[content.options.atom]
         end
      end
      if type(text) ~= "string" then
         SU.error("mo command contains content which is not text")
      end
      return b.text("operator", attributes, script, text)
   elseif content.command == "mn" then
      local script = content.options.mathvariant and mathVariantToScriptType(content.options.mathvariant)
         or scriptType.upright
      local text = content[1]
      if type(text) ~= "string" then
         SU.error("mn command contains content which is not text")
      end
      if string.sub(text, 1, 1) == "-" then
         text = "−" .. string.sub(text, 2)
      end
      return b.text("number", {}, script, text)
   elseif content.command == "mspace" then
      return b.space(content.options.width, content.options.height, content.options.depth)
   elseif content.command == "msub" then
      local children = convertChildren(content)
      if #children ~= 2 then
         SU.error("Wrong number of children in msub")
      end
      return b.newSubscript({ base = children[1], sub = children[2] })
   elseif content.command == "msup" then
      local children = convertChildren(content)
      if #children ~= 2 then
         SU.error("Wrong number of children in msup")
      end
      return b.newSubscript({ base = children[1], sup = children[2] })
   elseif content.command == "msubsup" then
      local children = convertChildren(content)
      if #children ~= 3 then
         SU.error("Wrong number of children in msubsup")
      end
      return b.newSubscript({ base = children[1], sub = children[2], sup = children[3] })
   elseif content.command == "munder" then
      local children = convertChildren(content)
      if #children ~= 2 then
         SU.error("Wrong number of children in munder")
      end
      return b.newUnderOver({ base = children[1], sub = children[2] })
   elseif content.command == "mover" then
      local children = convertChildren(content)
      if #children ~= 2 then
         SU.error("Wrong number of children in mover")
      end
      return b.newUnderOver({ base = children[1], sup = children[2] })
   elseif content.command == "munderover" then
      local children = convertChildren(content)
      if #children ~= 3 then
         SU.error("Wrong number of children in munderover")
      end
      return b.newUnderOver({ base = children[1], sub = children[2], sup = children[3] })
   elseif content.command == "mfrac" then
      local children = convertChildren(content)
      if #children ~= 2 then
         SU.error("Wrong number of children in mfrac: " .. #children)
      end
      return SU.boolean(content.options.bevelled, false)
            and b.bevelledFraction(content.options, children[1], children[2])
         or b.fraction(content.options, children[1], children[2])
   elseif content.command == "msqrt" then
      local children = convertChildren(content)
      -- "The <msqrt> element generates an anonymous <mrow> box called the msqrt base
      return b.sqrt(b.stackbox("H", children))
   elseif content.command == "mroot" then
      local children = convertChildren(content)
      return b.sqrt(children[1], children[2])
   elseif content.command == "mtable" or content.command == "table" then
      local children = convertChildren(content)
      return b.table(children, content.options)
   elseif content.command == "mtr" then
      return b.mtr(convertChildren(content))
   elseif content.command == "mtd" then
      return b.stackbox("H", convertChildren(content))
   elseif content.command == "mtext" or content.command == "ms" then
      if #content > 1 then
         SU.error("Wrong number of children in " .. content.command .. ": " .. #content)
      end
      local text = content[1] or "" -- empty mtext is allowed, and found in examples...
      if type(text) ~= "string" then
         SU.error(content.command .. " command contains content which is not text")
      end
      -- MathML Core 3.2.1.1 Layout of <mtext> has some wording about forced line breaks
      -- and soft wrap opportunities: ignored here.
      -- There's also some explanations about CSS, italic correction etc. which we ignore too.
      text = text:gsub("[\n\r]", " ")
      return b.text("string", {}, scriptType.upright, text:gsub("%s+", " "))
   elseif content.command == "maction" then
      -- MathML Core 3.6: display as mrow, ignoring all but the first child
      return b.stackbox("H", { convertFirstChild(content) })
   elseif content.command == "mstyle" then
      -- It's an mrow, but with some style attributes that we ignore.
      SU.warn("MathML mstyle is not fully supported yet")
      return b.stackbox("H", convertChildren(content))
   elseif content.command == "mpadded" then
      -- MathML Core 3.3.6.1: The <mpadded> element generates an anonymous <mrow> box
      -- called the "impadded inner box"
      return b.padded(content.options, b.stackbox("H", convertChildren(content)))
   else
      SU.error("Unknown math command " .. content.command)
   end
end

local function handleMath (_, mbox, options)
   local mode = options and options.mode or "text"
   local counter = SU.boolean(options.numbered, false) and "equation"
   counter = options.counter or counter -- overrides the default "equation" counter

   if mode == "display" then
      mbox.mode = b.mathMode.display
   elseif mode == "text" then
      mbox.mode = b.mathMode.textCramped
   else
      SU.error("Unknown math mode " .. mode)
   end

   SU.debug("math", function ()
      return "Resulting mbox: " .. tostring(mbox)
   end)
   mbox:styleDescendants()
   mbox:shapeTree()

   if mode == "display" then
      -- See https://github.com/sile-typesetter/sile/issues/2160
      --    We are not exactly doing the right things here with respect to
      --    paragraphing expectations.
      -- The vertical penalty will flush the previous paragraph, if any.
      SILE.call("penalty", { penalty = SILE.settings:get("math.predisplaypenalty"), vertical = true })
      SILE.typesetter:pushExplicitVglue(SILE.settings:get("math.displayskip"))
      -- Repeating the penalty after the skip does not hurt but should not be
      -- necessary if our page builder did its stuff correctly.
      SILE.call("penalty", { penalty = SILE.settings:get("math.predisplaypenalty"), vertical = true })
      SILE.settings:temporarily(function ()
         -- Center the equation in the space available up to the counter (if any),
         -- respecting the fixed part of the left and right skips.
         local lskip = SILE.settings:get("document.lskip") or SILE.types.node.glue()
         local rskip = SILE.settings:get("document.rskip") or SILE.types.node.glue()
         SILE.settings:set("document.parindent", SILE.types.node.glue())
         SILE.settings:set("current.parindent", SILE.types.node.glue())
         SILE.settings:set("document.lskip", SILE.types.node.hfillglue(lskip.width.length))
         SILE.settings:set("document.rskip", SILE.types.node.glue(rskip.width.length))
         SILE.settings:set("typesetter.parfillskip", SILE.types.node.glue())
         SILE.settings:set("document.spaceskip", SILE.types.length("1spc", 0, 0))
         SILE.typesetter:pushHorizontal(mbox)
         SILE.typesetter:pushExplicitGlue(SILE.types.node.hfillglue())
         if counter then
            options.counter = counter
            SILE.call("increment-counter", { id = counter })
            SILE.call("math:numberingstyle", options)
         elseif options.number then
            SILE.call("math:numberingstyle", options)
         end
         -- The vertical penalty will flush the equation.
         -- It must be done in the temporary settings block, because these have
         -- to apply as line boxes are being built.
         SILE.call("penalty", { penalty = SILE.settings:get("math.postdisplaypenalty"), vertical = true })
      end)
      SILE.typesetter:pushExplicitVglue(SILE.settings:get("math.displayskip"))
      -- Repeating: Same remark as for the predisplay penalty above.
      SILE.call("penalty", { penalty = SILE.settings:get("math.postdisplaypenalty"), vertical = true })
   else
      SILE.typesetter:pushHorizontal(mbox)
   end
end

return { ConvertMathML, handleMath }
