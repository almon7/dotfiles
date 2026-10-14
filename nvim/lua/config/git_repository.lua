-- Compare Git repository identities without changing the configured transport.
return function(url)
  url = url:gsub("/+$", ""):gsub("%.git$", "")
  local host, owner, name = url:match("^%w+://([^/]+)/([^/]+)/([^/]+)$")
  if not host then
    host, owner, name = url:match("^[^@]+@([^:]+):([^/]+)/([^/]+)$")
  end
  if host then
    host = host:gsub("^.*@", ""):gsub(":%d+$", "")
    return (host .. "/" .. owner .. "/" .. name):lower()
  end
end
