// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick

// The words of the windows. English is in the code; other languages are here.
QtObject {
    readonly property string lang: { const a = Qt.application.arguments, i = a.indexOf("--lang"); return i > 0 ? a[i + 1] : Qt.locale().name.slice(0, 2) }
    function t(s) { return (words[lang] || {})[s] || s }
    readonly property var words: ({ pl: {
        "Messages": "Wiadomości", "Message": "Wiadomość", "Search": "Szukaj", "Send": "Wyślij", "Back": "Wróć", "Close": "Zamknij",
        "Asking the phone": "Pytam telefon", "No messages": "Brak wiadomości", "Nothing found": "Nic nie znaleziono",
        "Not sent": "Nie wysłano", "Not known if it was sent: look on the phone": "Nie wiadomo, czy poszło: sprawdź w telefonie", 
        "Write to %1": "Napisz do: %1", "too long": "za długie", "copied: %1": "skopiowane: %1", "Nobody is waiting": "Nikt nie czeka", "Waiting for you: %1": "Czeka na Ciebie: %1",
        "Not connected": "Brak połączenia", "a code, %1": "kod, %1", "just now": "przed chwilą", "battery %1%": "bateria %1%", "charging": "ładuje się",
        "Later": "Później", "Reply": "Odpisz", "Conversation": "Rozmowa", "Copy code": "Kopiuj kod", "Copy %1": "Kopiuj %1",
        "Calls": "Połączenia", "Call": "Zadzwoń", "Hidden number": "Numer zastrzeżony", "is calling": "dzwoni", "calling": "dzwonię", "on the phone, %1": "rozmowa, %1",
        "missed call, %1": "nieodebrane, %1", "call ended": "rozmowa zakończona", "The voice stays on the phone": "Głos zostaje w telefonie",
        "Decline": "Odrzuć", "Answer": "Odbierz", "End call": "Rozłącz", "Text": "Napisz", "Call back": "Oddzwoń",
        "Bluetooth for calls: is the same code on the phone?": "Bluetooth do rozmów: czy na telefonie jest ten sam kod?", "Calls can be heard here now": "Teraz rozmowy słychać na komputerze",
        "Bluetooth was not paired": "Bluetooth nie został sparowany",
        "All": "Wszystkie", "New": "Nowe", "Name, number or word": "Imię, numer albo słowo",
        "Yesterday": "Wczoraj",
        "Pairlume is not running": "Pairlume nie działa", "No phone is paired yet": "Żaden telefon nie jest sparowany", "%1 is not connected": "%1 nie jest połączony",
        "Texts are off on this computer": "SMS-y są wyłączone na tym komputerze", "connected": "połączony", "Allow texts": "Włącz SMS-y",
        "Texts need a yes from this computer too, not only from the phone.": "SMS-y potrzebują zgody także tego komputera, nie tylko telefonu.",
        "Shake your phone": "Potrząśnij telefonem", "Scan with your phone": "Zeskanuj telefonem", "Type this on your phone": "Wpisz to w telefonie",
        "Connected": "Połączono", "That did not work": "Nie udało się", "with Pairlume open, on the same Wi-Fi": "z otwartym Pairlume, w tym samym Wi-Fi",
        "Is the same code on its screen?": "Czy na nim jest ten sam kod?", "Start pairlumed, this window will notice": "Uruchom pairlumed, okno to zauważy",
        "Shake": "Potrząśnij", "QR code": "Kod QR", "Digits": "Cyfry", "Not the same": "Inny", "They match": "Taki sam", "Try again": "Jeszcze raz",
        "No phone in two minutes": "Przez dwie minuty nie było telefonu", "Pairing was stopped": "Parowanie przerwane",
        "The codes were not the same, or the phone went away": "Kody się nie zgadzały albo telefon zniknął", "QR code for pairing": "Kod QR do parowania"
    } })
}
