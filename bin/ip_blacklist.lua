local redis_service = ngx.var.redis_service
local redis_port = tonumber(ngx.var.redis_port)
local redis_db = tonumber(ngx.var.redis_db)
local black_count = tonumber(ngx.var.black_count)
local black_rule_unit_time = tonumber(ngx.var.black_rule_unit_time)
local cache_ttl = tonumber(ngx.var.black_ttl)
local remote_ip = ngx.var.remote_addr

-- 计数
function my_count(redis, status_key, count_key)
    local key = status_key
    local key_connect_count = count_key

    local Status = redis:get(key)
    local count = redis:get(key_connect_count)

    if Status ~= ngx.null then
        -- 状态为connect 且 count不为空 且 count <= 拉黑次数
        if (Status == "Connect" and count ~= ngx.null and tonumber(count) <= black_count) then
            -- 再读一次
            count = redis:incr(key_connect_count)
            ngx.log(ngx.ERR, "count:", count) 
            if count ~= ngx.null then
                if tonumber(count) > black_count then
                    redis:del(key_connect_count)
                    redis:set(key,"Black")
                    -- 永久封禁
                    -- Redis:expire(key,cache_ttl)
                else
                    redis:expire(key_connect_count,black_rule_unit_time)
                end
            end
        else
            ngx.log(ngx.ERR,"The visit is blocked by the blacklist because it is too frequent. Please visit later.")
            return ngx.exit(ngx.HTTP_FORBIDDEN)
        end
    else
        local count = redis:get(key)
        if count == ngx.null then
            redis:del(key_connect_count)
        end
        redis:set(key,"Connect")
        redis:set(key_connect_count,1)
        redis:expire(key,black_rule_unit_time)
        redis:expire(key_connect_count,black_rule_unit_time)
    end
end 

-- 读取token
local token
local header = ngx.req.get_headers()["Authorization"]
if header ~= nil then
    token = string.match(header, 'token (%x+)')
end

local redis_connect_timeout = 60
local redis = require "resty.redis"
local Redis = redis:new()
local auto_blacklist_key = ngx.var.auto_blacklist_key

Redis:set_timeout(redis_connect_timeout)

local RedisConnectOk,ReidsConnectErr = Redis:connect(redis_service,redis_port)
local res = Redis:auth("password");

if not RedisConnectOk then
    ngx.log(ngx.ERR,"ip_blacklist connect Redis Error :" .. ReidsConnectErr)
else
    -- 连接成功
    Redis:select(redis_db)

    local key = auto_blacklist_key..":"..remote_ip
    local key_connect_count = auto_blacklist_key..":key_connect_count:"..remote_ip

    my_count(Redis, key, key_connect_count)

    if token ~= nil then
        local token_key, token_key_connect_count
        token_key = auto_blacklist_key..":"..token
        token_key_connect_count = auto_blacklist_key..":key_connect_count:"..token
        my_count(Redis, token_key, token_key_connect_count)
    end
end
