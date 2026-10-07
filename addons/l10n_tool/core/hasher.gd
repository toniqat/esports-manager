@tool
extends RefCounted

## 원문 해시 — 설계서 §4.3. `\r\n` → `\n` 만 정규화(앞뒤 공백은 자르지 않음),
## UTF-8 SHA-1 소문자 hex 앞 8자. NFC 정규화는 하지 않는다(W003 이 대신 잡는다).

static func hash_text(text: String) -> String:
	return text.replace("\r\n", "\n").sha1_text().substr(0, 8)
