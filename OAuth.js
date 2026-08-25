.pragma Library

var TOKENS_URL = Qt.resolvedUrl("tokens.json")
var AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
var TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
var REDIRECT_URI = "http://localhost:1"
var SCOPE = "https://www.googleapis.com/auth/calendar.readonly"

function authUrl(clientId) {
    return AUTH_ENDPOINT
        + "?client_id=" + encodeURIComponent(clientId)
        + "&redirect_uri=" + encodeURIComponent(REDIRECT_URI)
        + "&response_type=code"
        + "&scope=" + encodeURIComponent(SCOPE)
        + "&access_type=offline"
        + "&prompt=consent"
}

function exchangeCode(clientId, clientSecret, code, callback) {
    var xhr = new XMLHttpRequest()
    xhr.open("POST", TOKEN_ENDPOINT)
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                var tokens = {
                    access_token: data.access_token,
                    refresh_token: data.refresh_token || null,
                    expires_at: Date.now() + (data.expires_in * 1000),
                    client_id: clientId,
                    client_secret: clientSecret
                }
                _save(tokens)
                callback(true, null)
            } else {
                var errMsg = "Token exchange failed"
                try { errMsg += ": " + JSON.parse(xhr.responseText).error_description } catch(e) {}
                callback(false, errMsg)
            }
        }
    }
    xhr.send(
        "client_id=" + encodeURIComponent(clientId)
        + "&client_secret=" + encodeURIComponent(clientSecret)
        + "&code=" + encodeURIComponent(code)
        + "&grant_type=authorization_code"
        + "&redirect_uri=" + encodeURIComponent(REDIRECT_URI)
    )
}

function refreshAccessToken(tokens, callback) {
    if (!tokens || !tokens.refresh_token || !tokens.client_id || !tokens.client_secret) {
        callback(false, null)
        return
    }
    var xhr = new XMLHttpRequest()
    xhr.open("POST", TOKEN_ENDPOINT)
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                tokens.access_token = data.access_token
                tokens.expires_at = Date.now() + (data.expires_in * 1000)
                _save(tokens)
                callback(true, tokens.access_token)
            } else {
                callback(false, null)
            }
        }
    }
    xhr.send(
        "client_id=" + encodeURIComponent(tokens.client_id)
        + "&client_secret=" + encodeURIComponent(tokens.client_secret)
        + "&refresh_token=" + encodeURIComponent(tokens.refresh_token)
        + "&grant_type=refresh_token"
    )
}

function getValidToken(tokens, callback) {
    if (!tokens || !tokens.access_token) { callback(false, null); return }
    if (Date.now() < tokens.expires_at - 60000) {
        callback(true, tokens.access_token)
    } else {
        refreshAccessToken(tokens, callback)
    }
}

function loadTokens() {
    try {
        var raw = Qt.include(TOKENS_URL)
        if (raw && raw !== "") return JSON.parse(raw)
    } catch(e) {}
    return null
}

function _save(tokens) {
    try {
        var json = JSON.stringify(tokens, null, 2)
        // Qt.include is read-only; write via a helper
        _writeFile(TOKENS_URL, json)
    } catch(e) {}
}

function _writeFile(url, content) {
    // Use XMLHttpRequest to write to a local file via file:// protocol
    // Fallback: store in memory only (tokens lost on restart)
    try {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", url, false)
        xhr.send(content)
    } catch(e) {}
}

function clearTokens() {
    try { _writeFile(TOKENS_URL, "") } catch(e) {}
}

function isConfigured(tokens) {
    return tokens && tokens.client_id && tokens.client_secret && tokens.access_token
}

function isAuthenticated(tokens) {
    return isConfigured(tokens) && tokens.refresh_token
}
