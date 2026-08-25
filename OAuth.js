var AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
var TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
var REDIRECT_URI = "http://localhost:1"
var SCOPE = "https://www.googleapis.com/auth/calendar.readonly"

var DEFAULT_CLIENT_ID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
var DEFAULT_CLIENT_SECRET = "YOUR_CLIENT_SECRET"

function getClientId(settings) {
    return (settings && settings.client_id) ? settings.client_id : DEFAULT_CLIENT_ID
}

function getClientSecret(settings) {
    return (settings && settings.client_secret) ? settings.client_secret : DEFAULT_CLIENT_SECRET
}

function authUrl(settings) {
    return AUTH_ENDPOINT
        + "?client_id=" + encodeURIComponent(getClientId(settings))
        + "&redirect_uri=" + encodeURIComponent(REDIRECT_URI)
        + "&response_type=code"
        + "&scope=" + encodeURIComponent(SCOPE)
        + "&access_type=offline"
        + "&prompt=consent"
}

function exchangeCode(settings, code, callback) {
    var clientId = getClientId(settings)
    var clientSecret = getClientSecret(settings)
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

function refreshAccessToken(settings, callback) {
    if (!settings || !settings.refresh_token) { callback(false, null); return }
    var clientId = getClientId(settings)
    var clientSecret = getClientSecret(settings)
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
        + "&refresh_token=" + encodeURIComponent(settings.refresh_token)
        + "&grant_type=refresh_token"
    )
}

function getValidToken(settings, callback) {
    if (!settings || !settings.access_token) { callback(false, null); return }
    if (Date.now() < (settings.expires_at || 0) - 60000) {
        callback(true, settings.access_token)
    } else {
        refreshAccessToken(settings, callback)
    }
}

function isConfigured(s) {
    return true
}

function isAuthenticated(s) {
    return !!(s && s.access_token && s.refresh_token)
}
