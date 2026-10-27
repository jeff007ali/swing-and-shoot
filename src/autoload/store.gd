extends Node
## In-app purchases (§7, Phase 7 stub). The interface the game will use for cosmetics and the
## battle pass; this build has no store: every default item is owned, nothing can be bought.
## A later version backs it with App Store / Play Store billing through Godot's platform plugins.

signal purchase_finished(product_id: StringName, ok: bool, message: String)

## Cosmetics owned by everyone (the four MVP skins).
const FREE_ITEMS: Array[StringName] = [&"alien_green", &"alien_pink", &"alien_yellow", &"alien_purple"]


func is_available() -> bool:
	return false


## Products for sale: {id, name, price}. None in this build.
func products() -> Array[Dictionary]:
	return []


func is_owned(product_id: StringName) -> bool:
	return product_id in FREE_ITEMS


func purchase(product_id: StringName) -> void:
	purchase_finished.emit.call_deferred(product_id, false, "The store isn't available in this version.")


func restore_purchases() -> void:
	pass
