;;; kuro-input-keys-data.el --- Static KKP constants for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Kitty Keyboard Protocol constants shared by `kuro-input-keys.el' and
;; navigation helpers.

;;; Code:

(defconst kuro--kkp-disambiguate  #x01
  "KKP flag for disambiguating escape codes.")
(defconst kuro--kkp-report-events #x02
  "KKP flag: report key press/repeat/release event types.")
(defconst kuro--kkp-all-escape    #x08
  "KKP flag for reporting all keys as escape codes.")

;; KKP codepoints for functional (non-Unicode) keys.
;; Source: https://sw.kovidgoyal.net/kitty/keyboard-protocol/#functional-keys
(defconst kuro--kkp-cp-up        57352)
(defconst kuro--kkp-cp-down      57353)
(defconst kuro--kkp-cp-left      57350)
(defconst kuro--kkp-cp-right     57351)
(defconst kuro--kkp-cp-home      57356)
(defconst kuro--kkp-cp-end       57357)
(defconst kuro--kkp-cp-insert    57348)
(defconst kuro--kkp-cp-delete    57349)
(defconst kuro--kkp-cp-page-up   57354)
(defconst kuro--kkp-cp-page-down 57355)
(defconst kuro--kkp-cp-f1        57364)
(defconst kuro--kkp-cp-f2        57365)
(defconst kuro--kkp-cp-f3        57366)
(defconst kuro--kkp-cp-f4        57367)
(defconst kuro--kkp-cp-f5        57368)
(defconst kuro--kkp-cp-f6        57369)
(defconst kuro--kkp-cp-f7        57370)
(defconst kuro--kkp-cp-f8        57371)
(defconst kuro--kkp-cp-f9        57372)
(defconst kuro--kkp-cp-f10       57373)
(defconst kuro--kkp-cp-f11       57374)
(defconst kuro--kkp-cp-f12       57375)

(provide 'kuro-input-keys-data)

;;; kuro-input-keys-data.el ends here
