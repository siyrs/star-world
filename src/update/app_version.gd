class_name StarWorldAppVersion
extends RefCounted

const CURRENT_VERSION := "1.0.0"
const REPOSITORY := "siyrs/star-world"
const RELEASE_API_URL := "https://api.github.com/repos/%s/releases/latest" % REPOSITORY
const PACKAGE_ASSET_NAME := "StarWorld-Windows-x86_64.zip"
const CHECKSUM_ASSET_NAME := "StarWorld-Windows-x86_64.zip.sha256"
const EXECUTABLE_NAME := "StarWorld.exe"
const UPDATE_MANIFEST_NAME := "update-manifest.json"
const UPDATER_PROTOCOL_VERSION := 1


static func display_version() -> String:
	return "v%s" % CURRENT_VERSION
