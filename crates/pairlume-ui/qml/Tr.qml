// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick

// The words of the windows. English is in the code; other languages are here.
QtObject {
    readonly property string lang: { const a = Qt.application.arguments, i = a.indexOf("--lang"); return i > 0 ? a[i + 1] : Qt.locale().name.slice(0, 2) }
    function t(s) { return (words[lang] || {})[s] || s }
    readonly property var words: ({ pl: {
        "Messages": "Wiadomości", "Message": "Wiadomość", "Search": "Szukaj", "Send": "Wyślij", "Back": "Wróć", "Close": "Zamknij",
        "Choose a conversation": "Wybierz rozmowę", "Asking the phone": "Pytam telefon", "No messages": "Brak wiadomości", "Nothing found": "Nic nie znaleziono",
        "Not sent": "Nie wysłano", "Not known if it was sent: look on the phone": "Nie wiadomo, czy poszło: sprawdź w telefonie", "Sending": "Wysyłam",
        "Today": "Dzisiaj", "Yesterday": "Wczoraj",
        "Pairlume is not running": "Pairlume nie działa", "No phone is paired yet": "Żaden telefon nie jest sparowany", "%1 is not connected": "%1 nie jest połączony",
        "Texts are off for %1. To turn them on:\npairlume allow \"%1\" sms": "SMS-y są wyłączone dla %1. Aby włączyć:\npairlume allow \"%1\" sms",
        "Shake your phone": "Potrząśnij telefonem", "Scan with your phone": "Zeskanuj telefonem", "Type this on your phone": "Wpisz to w telefonie",
        "Connected": "Połączono", "That did not work": "Nie udało się", "with Pairlume open, on the same Wi-Fi": "z otwartym Pairlume, w tym samym Wi-Fi",
        "Is the same code on its screen?": "Czy na nim jest ten sam kod?", "Start pairlumed, this window will notice": "Uruchom pairlumed, okno to zauważy",
        "Shake": "Potrząśnij", "QR code": "Kod QR", "Digits": "Cyfry", "Not the same": "Inny", "They match": "Taki sam", "Try again": "Jeszcze raz",
        "No phone in two minutes": "Przez dwie minuty nie było telefonu", "Pairing was stopped": "Parowanie przerwane",
        "The codes were not the same, or the phone went away": "Kody się nie zgadzały albo telefon zniknął", "QR code for pairing": "Kod QR do parowania"
    } })
}
