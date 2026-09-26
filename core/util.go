package kitecore

import "encoding/base64"

func decodeB64(s string) (string, error) {
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.RawStdEncoding, base64.URLEncoding, base64.RawURLEncoding} {
		if b, err := enc.DecodeString(s); err == nil {
			return string(b), nil
		}
	}
	_, err := base64.StdEncoding.DecodeString(s)
	return "", err
}
