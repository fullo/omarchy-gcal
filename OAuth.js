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
                callback(true, {
                    access_token: data.access_token,
                    refresh_token: data.refresh_token || null,
                    expires_at: Date.now() + (data.expires_in * 1000)
                })
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

function refreshAccessToken(clientId, clientSecret, refreshToken, callback) {
    if (!refreshToken) { callback(false, null); return }
    var xhr = new XMLHttpRequest()
    xhr.open("POST", TOKEN_ENDPOINT)
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                callback(true, {
                    access_token: data.access_token,
                    expires_at: Date.now() + (data.expires_in * 1000)
                })
            } else {
                callback(false, null)
            }
        }
    }
    xhr.send(
        "client_id=" + encodeURIComponent(clientId)
        + "&client_secret=" + encodeURIComponent(clientSecret)
        + "&refresh_token=" + encodeURIComponent(refreshToken)
        + "&grant_type=refresh_token"
    )
}

function getValidToken(settings, callback) {
    if (!settings || !settings.access_token) { callback(false, null); return }
    if (Date.now() < (settings.expires_at || 0) - 60000) {
        callback(true, settings.access_token)
    } else if (settings.refresh_token) {
        refreshAccessToken(settings.client_id, settings.client_secret, settings.refresh_token, callback)
    } else {
        callback(false, null)
    }
}

function isConfigured(s) {
    return s && s.client_id && s.client_secret
}

function isAuthenticated(s) {
    return isConfigured(s) && s.access_token && s.refresh_token
}
