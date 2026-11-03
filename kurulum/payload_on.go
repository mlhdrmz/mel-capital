//go:build payload

package main

import _ "embed"

// Uygulama: Flutter derlemesinin Release klasörü (zip). Kaldır.exe: kaldırma programı.
//
//go:embed payload/uygulama.zip
var appZip []byte

//go:embed payload/kaldir.exe
var kaldirExe []byte
