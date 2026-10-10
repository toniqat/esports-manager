class_name CurrencyShopPopup
extends Control

# Lobby currency shop — opened by the top-right wallet pills (`LobbyScreen.open_wallet`).
# A sheet drops from the top edge (height = content); the floating close capsule sits bottom-right.
#   ┌ 재화 구매                                             ┐
#   │ 재화 교환      — 3 × 2 tiles: premium → coin bundles   │
#   │ 유료 재화 충전 — 3 × 2 tiles: KRW → premium packs       │
#   └ dev note (nothing is charged)                          ┘
# Rows = `currency_products.csv` via `ShopCatalog.currency_products(section)`; a tap buys at
# once (`ShopCatalog.buy_currency_product`), saves the profile, refreshes the lobby wallet and
# shows the lobby toast. KRW products are dev purchases: the premium amount is simply granted.
#
# - Layout lives in `UI_View_CurrencyShopPopup.tscn` (+ `UI_Comp_CurrencyShopProduct.tscn`);
#   build with `create()`. A Control child of the lobby (toast z 5 floats over it).
# - Code owns: tile count per grid (`_sync_items` — reuses the scene's preview tiles), tile
#   texts / icons, the price pill variation (premium vs KRW), safe-area offsets, the slide.

signal closed

const SCENE_PATH: String = "res://features/meta/shop/UI_View_CurrencyShopPopup.tscn"
const TILE_SCENE: String = "res://features/meta/shop/UI_Comp_CurrencyShopProduct.tscn"

## Profile currency key → icon (also the lobby wallet pills).
const CURRENCY_ICONS: Dictionary = {
	"outgame": "res://resources/images/ui/lobby/currency_coin.svg",
	"premium": "res://resources/images/ui/lobby/currency_gem.svg",
}

var _lobby = null          # LobbyScreen (untyped: duck-typed services; null in the F6 preview)
var _pm: Node
var _sheet_rest: float = 0.0
var _anim: Tween


static func create() -> CurrencyShopPopup:
	var p: CurrencyShopPopup = (load(SCENE_PATH) as PackedScene).instantiate()
	p.visible = false
	return p


static func currency_icon(key: String) -> Texture2D:
	return load(String(CURRENCY_ICONS.get(key, CURRENCY_ICONS["outgame"]))) as Texture2D


func _ready() -> void:
	_pm = get_node("/root/ProfileManager")
	%Dim.pressed.connect(close)
	%FloatingCloseButton_Close.pressed.connect(close)
	if UiPreview.is_standalone(self):
		_fill_preview()


func open(lobby: Node) -> void:
	_lobby = lobby
	# The lobby root sits below the notch: dim + sheet reach up over the notch band.
	ScreenMetrics.extend_background(%DimRect)
	ScreenMetrics.extend_background(%Dim)
	var sheet: Control = %Sheet
	ScreenMetrics.extend_background(sheet)
	(%Pad as MarginContainer).add_theme_constant_override("margin_top", int(ScreenMetrics.top_y()) + 28)
	UiHelpers.place_floating_close(%FloatingCloseButton_Close)
	_sheet_rest = sheet.offset_top
	_fill()
	visible = true
	_anim = UiHelpers.slide_top_sheet(self, _anim, self, sheet, _sheet_rest, true)


func close() -> void:
	if not visible:
		return
	_anim = UiHelpers.slide_top_sheet(self, _anim, self, %Sheet, _sheet_rest, false,
			func() -> void: visible = false)
	closed.emit()


func is_open() -> bool:
	return visible


func _fill() -> void:
	_fill_grid(%ExchangeGrid, ShopCatalog.currency_products(ShopCatalog.PRODUCT_EXCHANGE))
	_fill_grid(%CashGrid, ShopCatalog.currency_products(ShopCatalog.PRODUCT_CASH))


func _fill_grid(grid: Control, rows: Array) -> void:
	var tiles: Array = grid.get_children()
	while tiles.size() > rows.size():
		var extra: Node = tiles.pop_back()
		grid.remove_child(extra)
		extra.queue_free()
	while tiles.size() < rows.size():
		var t: Node = (load(TILE_SCENE) as PackedScene).instantiate()
		grid.add_child(t)
		tiles.append(t)
	for i in rows.size():
		var tile: Button = tiles[i]
		_fill_tile(tile, rows[i])
		for c in tile.pressed.get_connections():
			if (c["callable"] as Callable).get_object() == self:
				tile.pressed.disconnect(c["callable"])
		tile.pressed.connect(_on_tile_pressed.bind(int((rows[i] as Dictionary)["id"])))


func _fill_tile(tile: Button, row: Dictionary) -> void:
	var gain: String = String(row["gain_currency"])
	var bonus: int = int(row["bonus"])
	var krw: bool = String(row["price_currency"]) == ShopCatalog.PRICE_KRW
	(tile.get_node("%Icon") as TextureRect).texture = currency_icon(gain)
	(tile.get_node("%Amount") as Label).text = Loc.grouped(int(row["amount"]))
	(tile.get_node("%Bonus") as Label).text = Loc.t(L.SHOP_WALLET_BONUS, {"n": Loc.grouped(bonus)}) \
			if bonus > 0 else ""
	var price: PanelContainer = tile.get_node("%Price")
	price.theme_type_variation = &"CurrencyShopPriceCash" if krw else &"CurrencyShopPrice"
	var icon: TextureRect = tile.get_node("%PriceIcon")
	icon.visible = not krw
	if not krw:
		icon.texture = currency_icon(String(row["price_currency"]))
	var txt: Label = tile.get_node("%PriceText")
	txt.theme_type_variation = &"OnFillLabel" if krw else &"BodyLabel"
	txt.add_theme_font_size_override("font_size", OutgameTheme.FONT_BODY)
	txt.text = Loc.t(L.SHOP_WALLET_PRICE_KRW, {"price": Loc.grouped(int(row["price"]))}) if krw \
			else Loc.grouped(int(row["price"]))


func _on_tile_pressed(product_id: int) -> void:
	var err: String = ShopCatalog.buy_currency_product(_pm, product_id)
	if err != "":
		_toast(err, true)
		return
	var serr: String = _pm.save_profile()
	if serr != "":
		_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
		return
	Haptics.play(Haptics.Kind.SUCCESS)
	var row: Dictionary = ShopCatalog.currency_product(product_id)
	_toast(Loc.t(L.SHOP_WALLET_BOUGHT, {
		"name": ShopPopup.currency_label(String(row["gain_currency"])),
		"n": Loc.grouped(int(row["amount"])),
	}), false)
	if _lobby != null:
		_lobby.refresh_currency()


func _toast(msg: String, is_error: bool) -> void:
	if _lobby != null:
		_lobby.show_toast(msg, is_error)
	else:
		print("[CurrencyShopPopup] toast: %s%s" % [msg, " (error)" if is_error else ""])


## F6 단독 실행 미리보기 — 로비 없이 실제 표로 연다. 구매는 프로필을 바꾸므로 출력만 한다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	open(null)
	for grid in [%ExchangeGrid, %CashGrid]:
		for t in (grid as Control).get_children():
			UiPreview.mute(t as Button, self, "구매 " + String((t as Node).name))
