-- Prosody IM
-- Copyright (C) 2014 Daurnimator
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--
-- This module allows you to use cqueues with a net.server mainloop
--

local server = require "net.server";
local cqueues = require "cqueues";
assert(cqueues.VERSION >= 20150113, "cqueues newer than 20150113 required")

-- Create a single top level cqueue
local cq;

if server.cq then -- server provides cqueues object
	cq = server.cq;
elseif server.get_backend() == "select" and server._addtimer then -- server_select
	cq = cqueues.new();
	local function step()
		assert(cq:loop(0));
	end

	-- Use wrapclient (as wrapconnection isn't exported) to get server_select to watch cq fd
	local handler = server.wrapclient({
		getfd = function() return cq:pollfd(); end;
		settimeout = function() end; -- Method just needs to exist
		close = function() end; -- Need close method for 'closeall'
	}, nil, nil, {});

	-- Only need to listen for readable; cqueues handles everything under the hood
	-- readbuffer is called when `select` notes an fd as readable
	handler.readbuffer = step;

	-- Use server_select low lever timer facility,
	-- this callback gets called *every* time there is a timeout in the main loop
	server._addtimer(function(current_time)
		-- This may end up in extra step()'s, but cqueues handles it for us.
		step();
		return cq:timeout();
	end);
elseif server.event and server.base then -- server_event
	cq = cqueues.new();
	-- Only need to listen for readable; cqueues handles everything under the hood
	local EV_READ = server.event.EV_READ;
	-- Convert a cqueues timeout to an acceptable timeout for luaevent
	local function luaevent_safe_timeout(cq)
		local t = cq:timeout();
		-- if you give luaevent 0 or nil, it re-uses the previous timeout.
		if t == 0 then
			t = 0.000001; -- 1 microsecond is the smallest that works (goes into a `struct timeval`)
		elseif t == nil then -- pick something big if we don't have one
			t = 0x7FFFFFFF; -- largest 32bit int
		end
		return t
	end
	local event_handle;
	event_handle = server.base:addevent(cq:pollfd(), EV_READ, function(e)
			-- Need to reference event_handle or this callback will get collected
			-- This creates a circular reference that can only be broken if event_handle is manually :close()'d
			local _ = event_handle;
			-- Run as many cqueues things as possible (with a timeout of 0)
			-- If an error is thrown, it will break the libevent loop; but prosody resumes after logging a top level error
			assert(cq:loop(0));
			return EV_READ, luaevent_safe_timeout(cq);
		end, luaevent_safe_timeout(cq));
else
	error "NYI"
end

return {
	cq = cq;
}
