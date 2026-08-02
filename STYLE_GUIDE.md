# Roblox Lua Style Guide

This is the canonical coding style for this project. All Lua/Luau code written
here — by any person or any tool — must follow it. It is based on the official
[Roblox Lua Style Guide](https://roblox.github.io/lua-style-guide/).

Formatting is enforced with [StyLua](https://github.com/JohnnyMorganz/StyLua)
via `stylua.toml`; the rules StyLua cannot enforce (naming, structure, error
handling, and so on) are documented here and checked in code review.

## Guiding Principles

- The purpose of a style guide is to avoid arguments. There's no one right
  answer to how to format code, but consistency is important, so we agree to
  accept this one, somewhat arbitrary standard so we can spend more time
  writing code and less time arguing about formatting details in review.
- Optimize code for reading, not writing. You will write your code once. Many
  people will need to read it, from the reviewers, to anyone else that touches
  the code, to you when you come back to it in six months. All else being
  equal, consider what the diffs might look like — clean diffs make it easier
  to get your code reviewed.
- Avoid magic, such as surprising or dangerous Lua features. Magical code is
  really nice to use, until something goes wrong. Then no one knows why it
  broke or how to fix it. Metatables are a good example of a powerful feature
  that should be used with care.
- Be consistent with idiomatic Lua when appropriate.

## File Structure

Files should consist of these things (if present) in order:

1. An optional block comment talking about why this file exists. Don't attach
   the file name, author, or date — version control tells us those.
2. Services used by the file, using `GetService`
3. Module imports, using `require`
4. Module-level constants
5. Module-level variables and functions
6. The object the module returns
7. A return statement!

## Requires

### General

- All require calls must be at the top of a file, making dependencies static.
- Requires should be sorted alphabetically by module name.

### Requires Structure

Require statements can be grouped into blocks. Require blocks should mimic the
project's internal structure and consist of these things (if present) in order:

1. A definition of a common ancestor.
2. A block of all imported packages.
3. A block for definitions derived from packages, which may be broken down
   recursively by subfolder.
4. A block for modules imported from the same project, which may be broken
   down recursively by subfolder.

If blocks of requires are used:

- Blocks should be sorted alphabetically, first by the name of the subfolder
  which groups the block, and then by module name.
- If multiple require statements share a common path, prefer to move those to
  a separate block.

### Requiring Libraries

Libraries are projects which define an API for external consumers to use,
typically by providing a top-level table which requires other modules. This
allows libraries to have stable interfaces even when internal details change.

Library internals should require their public and private modules directly:

```lua
-- in MyLibrary/Foo.lua
local MyLibrary = script.Parent
local MyModule = require(MyLibrary.MyModule)
```

Consumers of libraries should require the API definition and then path to a
public module:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MyLibrary = require(ReplicatedStorage.MyLibrary)
local MyModule = MyLibrary.MyModule
```

### Example

For a project that looks like the following:

```
MyProject
|- FooBar
|  |- Foo.lua
|  |- Bar.lua
|- MyClass.lua
|- Packages
|  |- Baz.lua
|     |- Bazifyer.lua
|     |- UnBazifyer.lua
```

MyClass should define the following import block:

```lua
-- 1. A definition of a common ancestor.
-- Use a relative path to make sure your project works in multiple locations!
local MyProject = script.Parent

-- 2. A block of all imported packages.
-- Baz is a library we depend on, so we require its API directly...
local Baz = require(MyProject.Packages.Baz)

-- 3. A block for definitions derived from packages.
-- ...and then access its members through that API.
local Bazifyer = Baz.Bazifyer
local UnBazifyer = Baz.UnBazifyer

-- 4. A block for modules imported from the same project.
-- Defining the path to FooBar separately makes it faster to write and read!
local FooBar = MyProject.FooBar
local Foo = require(FooBar.Foo)
local Bar = require(FooBar.Bar)
```

## Metatables

Metatables are an incredibly powerful Lua feature. We limit their use to two
cases:

- Implementing prototype-based classes
- Guarding against typos

### Prototype-based classes

The method below is recommended because it takes advantage of Luau's typing
system. A strongly-typed class definition documents expected use and lets
analysis tools warn against possible bugs.

First up, create a regular, empty table, then assign the `__index` member on
the class back to itself. This lets us use the class's table as the metatable
for instances as well — like `prototype` in JavaScript:

```lua
local MyClass = {}
MyClass.__index = MyClass
```

To support strict type inference, describe the shape of the class. This
introduces some redundancy (members are specified twice — once in the type
definition, once when building the instance), but warnings will be flagged if
the two definitions fall out of sync:

```lua
-- Export the type if you'd like to use it outside this module
export type ClassType = typeof(setmetatable(
	{} :: {
		property: number,
	},
	MyClass
))
```

Create a default constructor named `new` by convention, returning `ClassType`:

```lua
function MyClass.new(property: number): ClassType
	local self = {
		-- Define members of the instance here, even if they're `nil` by default.
		property = property,
	}

	-- Tell Lua to fall back to looking in MyClass.__index for missing fields.
	setmetatable(self, MyClass)

	return self
end
```

Define methods using the dot (`.`) style so the type of `self` can be
annotated explicitly as `ClassType`. Methods defined this way are still
invoked on instances with a colon as expected:

```lua
function MyClass.addOne(self: ClassType)
	self.property += 1
end
```

Using the class:

```lua
local instance = MyClass.new(0)

-- Properties on the instance are visible, since it's just a table:
print(tostring(instance.property)) -- "0"

-- Methods are pulled from MyClass because of our metatable:
instance:addOne()
print(tostring(instance.property)) -- "1"
```

Further additions you can make to your class as needed:

- Introduce a `__tostring` metamethod to make debugging easier
- Define quasi-private members using two underscores as a prefix
- Add a method to check type given an instance, like:

```lua
function MyClass.isMyClass(instance)
	return getmetatable(instance).__index == MyClass
end
```

### Guarding against typos

Indexing into a table in Lua gives you `nil` if the key isn't present, which
can cause errors that are difficult to trace! For types that act like enums,
carefully apply an `__index` metamethod that throws:

```lua
local MyEnum = {
	A = "A",
	B = "B",
	C = "C",
}

setmetatable(MyEnum, {
	__index = function(self, key)
		error(string.format("%q is not a valid member of MyEnum", tostring(key)), 2)
	end,
})
```

Since `__index` is only called when a key is missing, `MyEnum.A` still gives
back the expected value, but `MyEnum.FROB` will throw, helping track down bugs.

## General Punctuation

- Don't use semicolons `;`. They are generally only useful to separate
  multiple statements on a single line, but you shouldn't be putting multiple
  statements on a single line anyway.

## General Whitespace

- Indent with tabs.
- Keep lines under 100 columns wide, assuming four column wide tabs.
  - Luacheck isn't accurate with tab characters; favor StyLua instead.
- Wrap comments to 80 columns wide, assuming four column wide tabs. Short
  lines help improve readability of comment prose, but 80 is too restrictive
  for code.
- Don't leave whitespace at the end of lines. If your editor has an
  auto-trimming function, turn it on!
- Add a newline at the end of the file.
- No vertical alignment! It makes code more difficult to edit and often gets
  messed up by subsequent editors.

  ```lua
  -- Good:
  local frobulator = 132
  local grog = 17

  -- Bad:
  local frobulator = 132
  local grog       =  17
  ```

- Use a single empty line to express groups when useful. Do not start blocks
  with a blank line. Excess empty lines harm whole-file readability.

  ```lua
  local Foo = require(Common.Foo)

  local function gargle()
  	-- gargle gargle
  end

  Foo.frobulate()
  Foo.frobulate()

  Foo.munge()
  ```

- Use one statement per line. Put function bodies on new lines.

  ```lua
  -- Good:
  table.sort(stuff, function(a, b)
  	local sum = a + b
  	return math.abs(sum) > 2
  end)

  -- Bad:
  table.sort(stuff, function(a, b) local sum = a + b return math.abs(sum) > 2 end)
  ```

  This is especially true for functions that return multiple values. Compare:

  ```lua
  Rodux.Store.new(function(state) return state end, mockState, nil)
  Rodux.Store.new(function(state) return state, mockState end, nil)
  ```

  It's much easier to spot the mistake (and much harder to make it in the
  first place) if the function isn't on one line:

  ```lua
  Rodux.Store.new(function(state)
  	return state
  end, mockState, nil)
  Rodux.Store.new(function(state)
  	return state, mockState
  end, nil)
  ```

  This is also true for `if` blocks, even if their body is just a `return`
  statement:

  ```lua
  -- Good:
  if valueIsInvalid then
  	return
  end

  -- Bad:
  if valueIsInvalid then return end
  ```

  Most of the time this pattern is used for validating an input or condition.
  It's much easier to add logging or expand the conditional when the statement
  is broken across multiple lines, and it diffs better in code review.

- Put a space before and after operators, except when clarifying precedence.

  ```lua
  -- Good:
  print(5 + 5 * 6^2)

  -- Bad:
  print(5+5* 6 ^2)
  ```

- Put a space after each comma in tables and function calls.

  ```lua
  -- Good:
  local friends = {"bob", "amy", "joe"}
  foo(5, 6, 7)

  -- Bad:
  local friends = {"bob","amy" ,"joe"}
  foo(5,6 ,7)
  ```

- When creating blocks, inline any opening syntax elements.

  ```lua
  -- Good:
  local foo = {
  	bar = 2,
  }

  if foo then
  	-- do something
  end

  -- Bad:
  local foo =
  {
  	bar = 2,
  }

  if foo
  then
  	-- do something
  end
  ```

- Avoid putting curly braces for tables on their own line. Doing so harms
  readability, since it forces the reader to move to another line in an
  awkward spot in the statement.

  ```lua
  -- Good:
  local foo = {
  	bar = {
  		baz = "baz",
  	},
  }

  frob({
  	x = 1,
  })

  -- Bad:
  local foo =
  {
  	bar =

  	{
  		baz = "baz",
  	},
  }

  frob(
  {
  	x = 1,
  })
  ```

  Exception:

  ```lua
  -- In function calls with large inline tables or functions, sometimes it's
  -- more clear to put braces and functions on new lines:
  foo(
  	{
  		type = "foo",
  	},
  	function(something)
  		print("Hello,", something)
  	end
  )

  -- As opposed to:
  foo({
  	type = "foo",
  }, function(something) -- How do we indent this line?
  	print("Hello,", something)
  end)
  ```

## Newlines in Long Expressions

- First, try to break up the expression so that no one part is long enough to
  need newlines. This isn't always the right answer — keeping an expression
  together is sometimes more readable than trying to parse how several small
  expressions relate — but it's worth pausing to consider which case you're in.
- It is often worth breaking up tables and arrays with more than two or three
  keys, or with nested sub-tables, even if it doesn't exceed the line length
  limit. Shorter, simpler tables can stay on one line though.
- Prefer adding the extra trailing comma to the elements within a multiline
  table or array. This makes it easier to add new items or rearrange existing
  items.
- Break dictionary-like tables with more than a couple keys onto multiple
  lines.

  ```lua
  -- Good:
  local foo = { type = "foo" }

  local bar = {
  	type = "bar",
  	phrase = "hooray",
  }

  -- It's also okay to use multiple lines for a single field
  local baz = {
  	type = "baz",
  }

  -- Bad:
  local stuff = { hello = "world", hola = "mundo", howdy = "y'all", sup = "homies" }
  ```

- Break list-like tables onto multiple lines however it makes sense, while
  following the line length limit.

  ```lua
  local libs = { "roact", "rodux", "testez", "cryo", "otter" }

  -- You can break these onto multiple lines, which makes diffs cleaner:
  local libs = {
  	"roact",
  	"rodux",
  	"testez",
  	"cryo",
  	"otter",
  }

  -- We can also group them, if grouping has useful information:
  local libs = {
  	"roact", "rodux", "cryo",

  	"testez", "otter",
  }
  ```

- For long argument lists or longer, nested tables, prefer to expand all the
  subtables. This makes for the cleanest diffs as further changes are made.

  ```lua
  local aTable = {
  	{
  		aLongKey = aLongValue,
  		anotherLongKey = anotherLongValue,
  	},
  	{
  		aLongKey = anotherLongValue,
  		anotherLongKey = aLongValue,
  	},
  }

  doSomething(
  	{
  		aLongKey = aLongValue,
  		anotherLongKey = anotherLongValue,
  	},
  	{
  		aLongKey = anotherLongValue,
  		anotherLongKey = aLongValue,
  	}
  )
  ```

  In situations where we only ever expect table literals, the following is
  acceptable, though automated tooling could change this later. This comes up
  a lot in Roact code (`doSomething` being `Roact.createElement`):

  ```lua
  local aTable = {{
  	aLongKey = aLongValue,
  	anotherLongKey = anotherLongValue,
  }, {
  	aLongKey = anotherLongValue,
  	anotherLongKey = aLongValue,
  }}

  doSomething({
  	aLongKey = aLongValue,
  	anotherLongKey = anotherLongValue,
  }, {
  	aLongKey = anotherLongValue,
  	anotherLongKey = aLongValue,
  })
  ```

  However, this case is less acceptable if there are any non-tables added to
  the mix. In that case, use the fully expanded style:

  ```lua
  -- Bad:
  doSomething({
  	aLongKey = aLongValue,
  	anotherLongKey = anotherLongValue,
  }, notATableLiteral, {
  	aLongKey = anotherLongValue,
  	anotherLongKey = aLongValue,
  })

  -- Good:
  doSomething(
  	{
  		aLongKey = aLongValue,
  		anotherLongKey = anotherLongValue,
  	},
  	notATableLiteral,
  	{
  		aLongKey = anotherLongValue,
  		anotherLongKey = aLongValue,
  	}
  )
  ```

- For long expressions, try to add newlines between logical subunits. If
  you're adding up lots of terms, place each term on its own line. If you
  have parenthesized subexpressions, put each subexpression on a newline.
  - Place the operator at the beginning of the new line. This makes it clearer
    at a glance that this is a continuation of the previous line.
  - If you need to add newlines within a parenthesized subexpression,
    reconsider whether you can use temporary variables. If you still can't,
    add a new level of indentation for the parts of the statement inside the
    open parentheses, much like you would with nested tables.
  - Don't put extra parentheses around the whole expression. This is
    necessary in Python, but Lua doesn't need anything special to indicate
    multiline expressions.
- For long conditions in `if` statements, put the condition in its own
  indented section and place the `then` on its own line to separate the
  condition from the body of the `if` block. Break up the condition as any
  other long expression.

  ```lua
  -- Good:
  if
  	someReallyLongCondition
  	and someOtherReallyLongCondition
  	and somethingElse
  then
  	doSomething()
  	doSomethingElse()
  end

  -- Bad:
  if someReallyLongCondition and someOtherReallyLongCondition
  	and somethingElse then
  	doSomething()
  	doSomethingElse()
  end
  ```

## if-then-else Expressions

- Use `if-then-else` expressions over the `x and y or z` pattern for selecting
  a value. They're safer, faster and more readable.

  ```lua
  -- Good:
  local scale = if someFlag() then 1 else 2

  -- Bad:
  local scale = someFlag() and 1 or 2
  ```

  `if` expressions require an `else`. In some cases, we only use
  `someFlag() and someObject` without the `or`. It's fine to either leave this
  as is (it doesn't have the same safety issues) or convert it to
  `if someFlag() then someObject else nil`.

- Don't get carried away trying to fit everything into one statement. These
  work best when they comfortably fit on one line. Keep diffs in mind,
  especially around flags — removing a condition from the middle of a line
  makes for a much less readable diff than removing it from between two lines.
- For multiple line `if` expressions, put the `then` and `else` at the start
  of new lines, each indented once.

  ```lua
  -- Good:
  local scale = if someReallyLongFlagName() or someOtherReallyLongFlagName()
  	then 1
  	else 2

  -- Bad:
  local scale = if someReallyLongFlagName() or someOtherReallyLongFlagName() then 1
  	else 2

  local scale = if someReallyLongFlagName() or someOtherReallyLongFlagName()
  	then 1 else 2
  ```

- If the `if` expression won't fit on three lines, convert it to a normal `if`
  statement:

  ```lua
  local scale
  if
  	someReallyLongFlagName()
  	or someOtherReallyLongFlagName()
  then
  	scale = Vector2.new(1, 1) + someVectorOffset
  		+ someOtherVector
  else
  	scale = Vector2.new(1, 1) + someNewVectorOffset
  		+ someNewOtherVector
  end
  ```

- An exception to the above is if the `if` expression is in the middle of a
  much larger expression (e.g. a table definition or function call) and
  converting it to a normal `if` statement would involve copying a large
  number of lines:

  ```lua
  local thing = makeSomething("Foo", {
  	OneChild = if someFlag()
  		then makeSomething("Bar", {
  			scale = 1,
  		})
  		else makeSomething("Bar", {
  			scale = 2,
  		}),
  	TwoChild = makeSomething("Baz"),
  })
  ```

- If the condition itself is too long to fit on one line, use a helper
  variable:

  ```lua
  -- Bad:
  local scale = if someReallyReallyLongFunctionName()
  	and someOtherReallyLongFunctionName()
  	then 1
  	else 2

  -- Good:
  local useNewScale = someReallyReallyLongFunctionName()
  	and someOtherReallyLongFunctionName()
  local scale = if useNewScale then 1 else 2
  ```

- While `if` expressions do support `elseif`, use it sparingly. If your set of
  conditions is complicated enough to need several elseifs, it may be
  difficult to read as a single expression. When an `if` expression with
  `elseif` clauses is preferred, put the `elseif (condition) then` on a new
  line just like `then` and `else`.
  - This is a tradeoff. It would be more consistent to put the second `then`
    on a newline indented again, but then you end up deeply indented, which
    isn't good.

  ```lua
  local scale = if someFlag() then 1 elseif someOtherFlag() then 0.5 else 2

  local thing = makeSomething("Foo", {
  	OneChild = if someFlag()
  		then makeSomething("Bar", {
  			scale = 1,
  		})
  		elseif someOtherFlag() then makeSomething("Bar", {
  			scale = 0.5,
  		})
  		else makeSomething("Bar", {
  			scale = 2,
  		}),
  	TwoChild = makeSomething("Baz"),
  })
  ```

## Blocks

- Don't use parentheses around the conditions in `if`, `while`, or `repeat`
  blocks. They aren't necessary in Lua!

  ```lua
  if CONDITION then
  end

  while CONDITION do
  end

  repeat
  until CONDITION
  ```

- Use `do` blocks if limiting the scope of a variable is useful.

  ```lua
  local getId
  do
  	local lastId = 0
  	getId = function()
  		lastId = lastId + 1
  		return lastId
  	end
  end
  ```

## Literals

- Use double quotes when declaring string literals.
  - Using single quotes means we have to escape apostrophes, which are often
    useful in English words.
  - Empty strings are easier to identify with double quotes, because in some
    fonts two single quotes might look like a single double quote
    (`""` vs `''`).

  ```lua
  -- Good:
  print("Here's a message!")

  -- Bad:
  print('Here\'s a message!')
  ```

  - Single quotes are acceptable if the string contains double quotes, to
    reduce escape sequences:

  ```lua
  print('Quoth the raven, "Nevermore"')
  ```

  - If the string contains both single and double quotes, prefer double
    quotes on the outside, but use your best judgement.

## Tables

- Avoid tables with both list-like and dictionary-like keys. Iterating over
  these mixed tables is troublesome.
- Iterate over list-like tables with `ipairs` and dictionary-like tables with
  `pairs`. This helps clarify what kind of table we're expecting in a given
  block of code!
- Add trailing commas in multi-line tables. This lets us re-sort lines with a
  single keypress and makes diffs cleaner when adding new items.

  ```lua
  local frobs = {
  	andrew = true,
  	billy = true,
  	caroline = true,
  }
  ```

## Functions

- Keep the number of arguments to a given function small, preferably 1 or 2.
- Always use parentheses when calling a function. Lua allows you to skip them
  in many cases, but the results are typically much harder to parse.

  ```lua
  -- Good:
  local x = doSomething("home")
  local y = doSomethingElse({u = 1, v = 2})

  -- Bad:
  local x = doSomething "home"
  local y = doSomethingElse{u = 1, v = 2}
  ```

  Of particular note, the last example — using the curly braces as if they
  were function call syntax — is common in other Lua codebases, but for
  consistency we don't use it in ours.

- Declare named functions using function-prefix syntax. Non-member functions
  should always be local.

  ```lua
  -- Good:
  local function add(a, b)
  	return a + b
  end

  -- Bad: this is a global!
  function add(a, b)
  	return a + b
  end

  -- Bad:
  local add = function(a, b)
  	return a + b
  end
  ```

  Exception:

  ```lua
  -- An exception can be made for late-initializing functions in conditionals:
  local doSomething

  if CONDITION then
  	function doSomething()
  		-- Version of doSomething with CONDITION enabled
  	end
  else
  	function doSomething()
  		-- Version of doSomething with CONDITION disabled
  	end
  end
  ```

- When declaring a function inside a table, use function-prefix syntax.
  Differentiate between `.` and `:` to denote intended calling convention.

  ```lua
  -- Good:
  -- This function should be called as Frobulator.new()
  function Frobulator.new()
  	return {}
  end

  -- This function should be called as Frobulator:frob()
  function Frobulator:frob()
  	print("Frobbing", self)
  end

  -- Bad:
  function Frobulator.garb(self)
  	print("Frobbing", self)
  end

  Frobulator.jarp = function()
  	return {}
  end
  ```

## Comments

- Wrap comments to 80 columns wide. It's easier to read comments with shorter
  lines, but fitting code into 80 columns can be challenging.
- Use single line comments for inline notes. If the comment spans multiple
  lines, use multiple single-line comments.

  ```lua
  -- This condition is really important because the world would blow up if it
  -- were missing.
  if not foo then
  	stopWorldFromBlowingUp()
  end
  ```

- Use block comments for documenting items:
  - Use a block comment at the top of files to describe their purpose.
  - Use a block comment before functions or objects to describe their intent.

  ```lua
  --[[
  	Shuts off the cosmic moon ray immediately.

  	Should only be called within 15 minutes of midnight Mountain Standard
  	Time, or the cosmic moon ray may be damaged.
  ]]
  local function stopCosmicMoonRay()
  end
  ```

- Comments should focus on why code is written a certain way instead of what
  the code is doing.

  ```lua
  -- Good:
  -- Without this condition, the aircraft hangar would fill up with water.
  if waterLevelTooHigh() then
  	drainHangar()
  end

  -- Bad:
  -- Check if the water level is too high.
  if waterLevelTooHigh() then
  	-- Drain the hangar
  	drainHangar()
  end
  ```

- No section comments. Comments that only exist to break up a large file are
  a code smell; you probably need to find some way to make your file smaller
  instead of working around that problem with section comments. Comments that
  only exist to demark already obvious groupings of code (e.g.
  `--- VARIABLES ---`) and overly stylized comments can actually make the
  code harder to read, not easier.

  Some ways of breaking up files:
  - Move inner classes and static functions into their own files, which
    aren't included in the public API. This also makes testing easier.
  - Check if there are any existing libraries that can simplify your code.

  If you can't break the file up and still feel like you need section
  headings, consider these alternatives:
  - If you want to put a section header on a group of functions, put that
    information in a block comment attached to the first function in that
    section. Make sure the comment is still about the function it's attached
    to, and write it so it's clear what's included in the section.
  - The same can be done for a group of variables in some cases. Consider
    whether one block comment, a normal comment on each variable, or just
    whitespace between groups would be more readable.
  - General organization of your code can aid readability while making
    logical sections more obvious. Module-level variables and functions can
    appear in any order, so you can sometimes put a group of variables above
    a group of functions to make a section.

## Naming

- Spell out words fully! Abbreviations generally make code easier to write,
  but harder to read.
- Use `PascalCase` names for class and enum-like objects.
- Use `PascalCase` for all Roblox APIs. `camelCase` APIs are mostly
  deprecated, but still work for now.
- Use `camelCase` names for local variables, member values, and functions.
- For acronyms within names, don't capitalize the whole thing. For example,
  `aJsonVariable` or `MakeHttpCall`.
- The exception to this is when the abbreviation represents a set. For
  example, in `anRGBValue` or `GetXYZ`. In these cases, `RGB` should be
  treated as an abbreviation of `RedGreenBlue` and not as an acronym.
- Use `LOUD_SNAKE_CASE` names for local constants.
- Prefix private members with an underscore, like `_camelCase`. Lua does not
  have visibility rules, but using a character like an underscore helps make
  private access stand out.
- A file's name should match the name of the object it exports. If your
  module exports a single function named `doSomething`, the file should be
  named `doSomething.lua`.

`FooThing.lua`:

```lua
local FOO_THRESHOLD = 6

local FooThing = {}

FooThing.someMemberConstant = 5

function FooThing.go()
	print("Foo Delta:", FooThing.someMemberConstant - FOO_THRESHOLD)
end

return FooThing
```

## Yielding

Do not call yielding functions on the main task. Wrap them in
`coroutine.wrap` or `delay`, and consider exposing a Promise or Promise-like
async interface for your own functions.

Pros:

- Roblox's yielding model makes calling asynchronous tasks transparent to the
  user, which lets users call complicated functions without understanding
  coroutines or other async primitives.

Cons:

- Unintended yielding can cause hard-to-track data races. Simple code
  involving callbacks can cause confusing bugs if the input callback yields:

```lua
local value = 0

local function doSomething(callback)
	local newValue = value + 1
	callback(newValue)
	value = newValue
end
```

## Error Handling

When writing functions that can fail, return `success, result`, use a
`Result` type, or use an async primitive that encodes failure, like
`Promise`.

Do not throw errors except when validating correct usage of a function.

```lua
local function thisCanFail(someValue)
	assert(typeof(someValue) == "string", "someValue must be a string!")

	if success() then
		return true, "Congratulations! You won!"
	else
		return false, Error.new("ERR_BLAH", "Something horrible failed!")
	end
end
```

Pros:

- Using exceptions lets unhandled errors bubble up 'automatically' to your
  caller
- Stack traces are automatically attached to errors

Cons:

- Lua can only throw strings as errors, which makes distinguishing between
  them very difficult
- Exceptions are not encoded into a function's contract explicitly. By
  returning `success, result`, you force your caller to consider whether an
  error will happen.

Exceptions:

- When calling functions that communicate failure by throwing, wrap calls in
  `pcall` and make it clear via comment what kinds of errors you're expecting
  to handle.

## General Roblox Best Practices

- All services should be referenced using `game:GetService` at the top of the
  file.
- When importing a module, use the name of the module for its variable name.
