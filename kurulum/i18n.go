package main

// Arayüz dili: önce komut satırı (--dil), sonra Mel Capital'in kendi dil ayarı
// (Belgeler\Mel Capital\Profiller\profiller.json), en son Windows'un dili. Türkçe değilse İngilizce.

import (
	"encoding/json"
	"os"
	"path/filepath"
)

var lang = "tr"

func setLanguage(flag string) {
	switch {
	case flag == "tr" || flag == "en":
		lang = flag
	case appLanguage() != "":
		lang = appLanguage()
	case uiLanguageTurkish():
		lang = "tr"
	default:
		lang = "en"
	}
}

// appLanguage, Mel Capital'de seçili dili okur (yoksa "").
func appLanguage() string {
	b, err := os.ReadFile(filepath.Join(dataDir(), "Profiller", "profiller.json"))
	if err != nil {
		return ""
	}
	var idx struct {
		Lang string `json:"lang"`
	}
	if json.Unmarshal(b, &idx) != nil || (idx.Lang != "tr" && idx.Lang != "en") {
		return ""
	}
	return idx.Lang
}

// T, dile göre metni seçer.
func T(tr, en string) string {
	if lang == "tr" {
		return tr
	}
	return en
}
