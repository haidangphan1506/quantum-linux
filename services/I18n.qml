pragma Singleton

import QtQuick
import Quickshell
import qs.services
import "../i18n/strings.js" as Strings

// Ngon ngu giao dien (Settings.ui.lang: "vi" | "en").
// Dung: text: I18n.t("Chuoi goc") - khoa la chuoi tieng Tay Ban Nha goc; neu chua dich thi hien chuoi goc.
// Binding nao goi I18n.t() se tu cap nhat khi doi ngon ngu (vi t() doc root.lang).
Singleton {
    id: root

    readonly property var languages: [
        { v: "vi", t: "Tiếng Việt", i: "translate" },
        { v: "en", t: "English", i: "language" }
    ]
    readonly property string lang: Settings.ui.lang === "en" ? "en" : "vi"
    readonly property var dict: lang === "en" ? Strings.en : Strings.vi
    // Locale cho ngay thang (ten thu, ten thang)
    readonly property var locale: Qt.locale(lang === "en" ? "en_US" : "vi_VN")

    function t(s: string): string {
        return root.dict[s] ?? s;
    }

    // Dinh dang ngay theo ngon ngu
    function date(d: var, fmt: string): string {
        return root.locale.toString(d, fmt);
    }

    // "31 de octubre de 2026" -> theo ngon ngu
    readonly property string longDate: lang === "en" ? "MMMM d, yyyy" : "d MMMM, yyyy"
    readonly property string dayMonth: lang === "en" ? "dddd, MMMM d" : "dddd, d MMMM"
    readonly property string dayMonthShort: lang === "en" ? "dddd, MMM d" : "dddd, d MMM"

    // Tieu de cot cua lich, bat dau tu thu Hai
    readonly property var weekdaysLetter: lang === "en" ? ["M", "T", "W", "T", "F", "S", "S"] : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
    readonly property var weekdaysShort: lang === "en" ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    function setLang(l: string): void {
        Settings.setUi("lang", l);
    }
}
