-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

module:depends("http");
local lfs = require "lfs";

local os_date = os.date;
local open = io.open;
local stat = lfs.attributes;

local http_base = module:get_option_string("http_files_dir", module:get_option_string("http_path", "www_files"));
local dir_indices = module:get_option("http_files_index", { "index.html", "index.htm" });

local mime_map = module:shared("mime").types;
if not mime_map then
	mime_map = {
		html = "text/html", htm = "text/html",
		xml = "application/xml",
		txt = "text/plain",
		css = "text/css",
		js = "application/javascript",
		png = "image/png",
		gif = "image/gif",
		jpeg = "image/jpeg", jpg = "image/jpeg",
		svg = "image/svg+xml",
	};
	module:shared("mime").types = mime_map;

	local mime_types, err = open(module:get_option_string("mime_types_file", "/etc/mime.types"),"r");
	if mime_types then
		local mime_data = mime_types:read("*a");
		mime_types:close();
		setmetatable(mime_map, {
			__index = function(t, ext)
				local typ = mime_data:match("\n(%S+)[^\n]*%s"..(ext:lower()).."%s") or "application/octet-stream";
				t[ext] = typ;
				return typ;
			end
		});
	end
end

local cache = setmetatable({}, { __mode = "kv" }); -- Let the garbage collector have it if it wants to.

function serve_file(event, path)
	local request, response = event.request, event.response;
	local orig_path = request.path;
	local full_path = http_base.."/"..path;
	local attr = stat(full_path);
	if not attr then
		return 404;
	end

	response.headers.last_modified = os_date('!%a, %d %b %Y %H:%M:%S GMT', attr.modification);

	local tag = ("%02x-%x-%x-%x"):format(attr.dev or 0, attr.ino or 0, attr.size or 0, attr.modification or 0);
	response.headers.etag = tag;
	if tag == request.headers.if_none_match then
		return 304;
	end

	local data = cache[path];
	if data then
		response.headers.content_type = data.content_type;
		data = data.data;
	elseif attr.mode == "directory" then
		if full_path:sub(-1) ~= "/" then
			response.headers.location = orig_path.."/";
			return 301;
		end
		for i=1,#dir_indices do
			if stat(full_path..dir_indices[i], "mode") == "file" then
				return serve_file(event, path..dir_indices[i]);
			end
		end

		-- TODO File listing
		return 403;
	else
		local f = open(full_path, "rb");
		data = f and f:read("*a");
		f:close();
		if not data then
			return 403;
		end
		local ext = path:match("%.([^.]*)$");
		local content_type = mime_map[ext];
		cache[path] = { data = data; content_type = content_type; };
		response.headers.content_type = content_type;
	end

	return response:send(data);
end

module:provides("http", {
	route = {
		["GET /*"] = serve_file;
	};
});

