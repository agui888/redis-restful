--file redisproxy.lua

local redis = require "resty.redis"
local cjson = require "cjson"
local red = redis:new()
red:set_timeout(1000)       -- 1 sec
local ok, err = red:connect('10.237.3.155',22121);
if not ok then
    ngx.say('failed to connect', err)
    return
end

local _M = loadfile('lua/commands.lua')()
local commands = {}

for i = 1, #_M do
    local cmd = _M[i]
    commands[cmd] = 
        function (...) 
            return red[cmd](red,...)
        end
end


function string:split(sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   self:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end


function struct_args(args)                --包装命令和参数
    local str_args = {}
    for i = 1, #args do
        str_args[#str_args + 1] = '\''..args[i]..'\''
    end
    local args_string = "return "..str_args[1]
    for i = 2, #str_args do
        args_string = args_string..','..str_args[i]
    end
    return args_string
end
    

table.loadstring = function(strData)
    local f = loadstring(strData)
    if f then
        return f()
    end
end

local configs = ngx.shared.configs
local commands  = configs:get('commands')
if not commands then
    ngx.log(ngx.INFO, 'err in get commands')
    ngx.exit(500)
end
commands = table.loadstring(commands)

local uri = ngx.var.uri
local uri_args = uri:split('/')
local cmd = uri_args[#uri_args]
local method = ngx.req.get_method()
local req_args
if method == 'POST' then
    ngx.req.read_body()
    req_args = ngx.req.get_post_args()
elseif method == 'GET' then
    req_args = ngx.req.get_uri_args()
end

local confdocs = commands[cmd]
if not confdocs then
    ngx.log(ngx.INFO, 'err to get cmd config')
    ngx.exit(500)
end

local redis_args = {}
local arg_index = configs:get('arg_index')
if not arg_index then
    ngx.log(ngx.INFO, 'error when get arg_index')
end
for i = 1, #confdocs[arg_index]['args'] do
    local arg = confdocs[arg_index]['args'][i]
    if arg.separate then
        sep_args = arg.name:split(',')
        for j = 1, #sep_args do
            table.insert(redis_args, sep_args[j])
        end
    else
        table.insert(redis_args, arg.name)
    end
end

for a, b in pairs(redis_args) do
    print (a, b)
end
ngx.exit(200)

local ok, err = red:set_keepalive(10000,100)
if not ok then
    ngx.say('failed to set keepalive: ', err)
    return
end
