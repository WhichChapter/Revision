--[[
    Revision GitHub constructor (initial replacement)
    Repository: WhichChapter/Revision
    This replaces the old file-hosting layer only. It deliberately does not
    emulate the old RIA/whitelist or cloud-profile service.
]]

local HttpService = game:GetService("HttpService")

local OWNER = "WhichChapter"
local REPOSITORY = "Revision"
local BRANCH = "main"
local ROOT = "Render-7cbf28cd0d8be6bd7c87ecd1c9eb4ec2898bc214"

local RAW_BASE = ("https://raw.githubusercontent.com/%s/%s/%s/%s/"):format(
    OWNER, REPOSITORY, BRANCH, ROOT
)
local API_BASE = ("https://api.github.com/repos/%s/%s/contents/%s/"):format(
    OWNER, REPOSITORY, ROOT
)

local function getRequestFunction()
    local candidates = {
        (syn and syn.request),
        (http and http.request),
        http_request,
        request
    }
    for _, candidate in ipairs(candidates) do
        if typeof(candidate) == "function" then
            return candidate
        end
    end
    return nil
end

local requestFunction = getRequestFunction()

local function encodeQuery(params)
    if typeof(params) ~= "table" or #params == 0 then
        return ""
    end

    local parts = {}
    for _, item in ipairs(params) do
        if typeof(item) == "table" and item.name ~= nil then
            table.insert(parts,
                HttpService:UrlEncode(tostring(item.name)) .. "=" ..
                HttpService:UrlEncode(tostring(item.value or ""))
            )
        end
    end
    return #parts > 0 and ("?" .. table.concat(parts, "&")) or ""
end

local function cleanPath(path)
    assert(typeof(path) == "string" and path ~= "", "A repository path is required")
    path = path:gsub("\\", "/"):gsub("^/+", "")
    assert(not path:find("..", 1, true), "Parent-directory paths are not allowed")
    assert(not path:find("[%c]"), "Control characters are not allowed in paths")
    return path
end

local function perform(url, method, headers, body)
    assert(requestFunction, "This executor does not expose a supported HTTP request function")
    local response = requestFunction({
        Url = url,
        URL = url,
        Method = method or "GET",
        Headers = headers or {
            ["Accept"] = "application/vnd.github+json",
            ["User-Agent"] = "Revision-GitHub-Loader"
        },
        Body = body
    })
    assert(typeof(response) == "table", "Executor returned an invalid HTTP response")
    local status = tonumber(response.StatusCode or response.Status or 0) or 0
    local responseBody = response.Body or response.body or ""
    return {
        ok = status >= 200 and status < 300,
        status = status,
        body = responseBody,
        headers = response.Headers or response.headers or {},
        json = function()
            local success, decoded = pcall(HttpService.JSONDecode, HttpService, responseBody)
            if not success then
                error("Response was not valid JSON: " .. tostring(decoded))
            end
            return decoded
        end
    }
end

local function githubFile(path)
    path = cleanPath(path)
    return perform(RAW_BASE .. path, "GET")
end

local http = {}

function http:getfile(path)
    local result = githubFile(path)
    assert(result.ok, ("GitHub download failed (%s): %s"):format(result.status, path))
    return result.body
end

function http:request(options)
    assert(typeof(options) == "table", "request expects an options table")
    local path = cleanPath(options.path or "")
    local subdomain = options.subdomain or "storage"

    -- GitHub Contents API replaces the old host's directory iteration.
    if options.params then
        local iterate = false
        for _, item in ipairs(options.params) do
            if item.name == "iterate" and tostring(item.value) == "true" then
                iterate = true
            end
        end

        if iterate then
            local directory = API_BASE .. path
            local result = perform(directory .. encodeQuery(options.params), "GET")
            if not result.ok then
                return result
            end

            local decoded = result.json()
            local names = {}
            if typeof(decoded) == "table" then
                for _, entry in ipairs(decoded) do
                    if entry.name then
                        table.insert(names, entry.name)
                    end
                end
            end

            local encoded = HttpService:JSONEncode({success = true, result = names})
            return {
                ok = true,
                status = result.status,
                body = encoded,
                headers = result.headers,
                json = function()
                    return {success = true, result = names}
                end
            }
        end
    end

    -- The old storage API exposed mutable profiles and authentication routes.
    -- GitHub Raw/Contents cannot safely replace those services.
    if path == "newria" or path == "configuration" or
        path:match("^configuration/") then
        return {
            ok = false,
            status = 501,
            body = "This legacy endpoint needs a real compatible backend; it is not a GitHub file.",
            headers = {},
            json = function()
                return {
                    success = false,
                    result = "Legacy RIA/profile API has not been migrated."
                }
            end
        }
    end

    if subdomain ~= "storage" then
        return {
            ok = false, status = 400,
            body = "Unsupported legacy subdomain: " .. tostring(subdomain),
            headers = {},
            json = function() return {} end
        }
    end

    return githubFile(path)
end

function http:getfilefromcloud()
    error("Cloud profile downloads require a compatible storage backend; GitHub Raw is read-only.")
end

function http:publishtocloud()
    error("Cloud profile publishing requires a secure write-service; never embed a GitHub token in an executor script.")
end

function http:getdiscord()
    error("Discord lookup has not been migrated to the GitHub file loader.")
end

function http:githubhash()
    return BRANCH
end

local crypt = {
    getSecretValueAsync = function(_, key)
        assert(typeof(key) == "string", "Secret key must be a string")
        if typeof(getgenv) == "function" and getgenv().getcustomasset then
            -- Secret APIs are executor-specific; do not pretend a missing secret exists.
        end
        return nil
    end,
    storeSecretValueAsync = function(_, key, value)
        error("Secure secret storage is executor-specific and is not implemented in this portable constructor.")
    end
}

-- Fail closed until a real RIA/whitelist service is connected.
local whitelist = {
    state = -1,
    get = function()
        return false
    end,
    registercommand = function()
        error("Whitelist commands require the original authorization service.")
    end
}

local constructor = {
    http = http,
    crypt = crypt,
    whitelist = whitelist,
    runtime = {
        name = "Revision GitHub constructor",
        version = "0.1.0"
    }
}

function constructor:uninject()
    if shared.rendervape and shared.rendervape.uninject then
        return shared.rendervape:uninject()
    end
end

function constructor:getplayertag()
    return nil
end

return constructor
