local fs = require "luacheck.fs"
local utils = require "luacheck.utils"

-- Only ?, *, ** and simple character classes (with ranges and negation) are supported.
-- Hidden files are not treated specially. Special characters can't be escaped.
-- In ranges, - can't be used literally.
local globbing = {}

local cur_dir = fs.current_dir()

local function is_regular_path(glob)
   return not glob:find("[*?%[]")
end

local function get_parts(path)
   local parts = {}

   for part in path:gmatch("[^"..utils.dir_sep.."]+") do
      table.insert(parts, part)
   end

   return parts
end

local function glob_pattern_escaper(c)
   return ((c == "*" or c == "?") and "." or "%")..c
end

local function glob_range_escaper(c)
   return c == "-" and c or ("%"..c)
end

local function glob_part_to_pattern(glob_part)
   local buffer = {"^"}
   local i = 1

   while i <= #glob_part do
      local bracketless
      bracketless, i = glob_part:match("([^%[]*)()", i)
      table.insert(buffer, (bracketless:gsub("%p", glob_pattern_escaper)))

      if glob_part:sub(i, i) == "[" then
         table.insert(buffer, "[")
         i = i + 1
         local first_char = glob_part:sub(i, i)

         if first_char == "!" then
            table.insert(buffer, "^")
         else
            table.insert(buffer, "%"..first_char)
         end

         bracketless, i = glob_part:match("([^%]]*)()", i + 1)
         table.insert(buffer, (bracketless:gsub("%p", glob_range_escaper)))
         table.insert(buffer, "]")
         i = i + 1
      end
   end

   table.insert(buffer, "$")
   return table.concat(buffer)
end

local function part_match(glob_part, path_part)
   return not not path_part:match(glob_part_to_pattern(glob_part))
end

local function parts_match(glob_parts, glob_i, path_parts, path_i)
   local glob_part = glob_parts[glob_i]

   if not glob_part then
      -- Reached glob end, path matches the glob or its subdirectory.
      -- E.g. path "foo/bar/baz/src.lua" matches glob "foo/*/baz".
      return true
   end

   if glob_part == "**" then
      -- "**" can consume any number of path parts.
      for i = path_i, #path_parts + 1 do
         if parts_match(glob_parts, glob_i + 1, path_parts, i) then
            return true
         end
      end

      return false
   end

   local path_part = path_parts[path_i]
   return path_part and part_match(glob_part, path_part) and parts_match(glob_parts, glob_i + 1, path_parts, path_i + 1)
end

-- Checks if a path matches a globbing pattern.
function globbing.match(glob, path)
   glob = fs.normalize(fs.join(cur_dir, glob))
   path = fs.normalize(fs.join(cur_dir, path))

   if is_regular_path(glob) then
      return fs.is_subpath(glob, path)
   end

   local glob_base, path_base
   glob_base, glob = fs.split_base(glob)
   path_base, path = fs.split_base(path)

   if glob_base ~= path_base then
      return false
   end

   local glob_parts = get_parts(glob)
   local path_parts = get_parts(path)
   return parts_match(glob_parts, 1, path_parts, 1)
end

return globbing