class_name CurrencyIcons
## Profile currency key → icon. Dependency-free on purpose: the lobby wallet pills need it on the
## first frame, and referencing `CurrencyShopPopup` there would compile the whole shop at boot.

const ICONS: Dictionary = {
	"outgame": "res://resources/images/ui/lobby/currency_coin.svg",
	"premium": "res://resources/images/ui/lobby/currency_gem.svg",
}


static func icon(key: String) -> Texture2D:
	return load(String(ICONS.get(key, ICONS["outgame"]))) as Texture2D
