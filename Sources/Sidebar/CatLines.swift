import Foundation

// MARK: - Rüdigers Sprüche
//
// Leitgedanke: Rüdiger kann lieb – ist aber ein Arschloch.
// Ton je Spruch: 0 = lieb, 1 = frech, 2 = schwarz/beleidigend.

/// Ein Spruch und ab welchem Ton er vorkommt.
struct CatLine {
    let tone: Int
    let text: String
    init(_ tone: Int, _ text: String) {
        self.tone = tone
        self.text = text
    }
}

enum CatLines {
    static let ask: [CatLine] = [
        .init(0, "Streichel mich!"),
        .init(0, "Kopf kraulen, bitte."),
        .init(1, "Hey. Streicheln. Jetzt."),
        .init(1, "Ich bin flauschig. Nutz das aus."),
        .init(1, "Streicheln, oder ich kotz auf die Tastatur."),
        .init(2, "Streichel mich, du Tastaturquäler!"),
        .init(2, "Hände weg von der Maus. Her mit der Hand."),
        .init(2, "Streichel mich. Ist eh das Produktivste, was du heute machst."),
    ]
    static let annoyed1: [CatLine] = [
        .init(0, "Hallooo? Ich warte!"),
        .init(1, "Haallooo, pennst du?"),
        .init(1, "Ich warte. Ich bin sehr gut im Warten. Und im Nachtragen."),
        .init(2, "Haallooo?! Pennst du, Schnarchnase?"),
        .init(2, "Bist du taub oder nur langsam?"),
    ]
    static let annoyed2: [CatLine] = [
        .init(0, "Du ignorierst mich, oder?"),
        .init(1, "Ich seh genau, dass du mich ignorierst."),
        .init(1, "Ignorier mich ruhig. Ich merk mir alles."),
        .init(2, "Ignorier mich ruhig weiter, du Flachpfeife."),
        .init(2, "Wow. Nicht mal Streicheln kriegst du hin."),
    ]
    static let annoyed3: [CatLine] = [
        .init(0, "Na gut. Dann schlaf ich halt."),
        .init(1, "Pff. Dann eben nicht. Beleidigt."),
        .init(1, "Ich kotz dir heute Nacht in die Schuhe. Nur so."),
        .init(2, "Weißt du was? Du kannst mich mal. Ich schlaf jetzt."),
        .init(2, "Ich merk mir das, du Trantüte. Rache ist ein Haarknäuel."),
    ]
    static let petted: [CatLine] = [
        .init(0, "Schnurrr …"),
        .init(0, "Na gut. Weitermachen."),
        .init(1, "Hmpf. War okay."),
        .init(1, "Mehr davon. Aber später."),
        .init(1, "Ich hab dich lieb. Fast so sehr wie mein Futter. Fast."),
        .init(2, "Endlich, du Trantüte."),
        .init(2, "Na also. Geht doch, Sesselpupser."),
        .init(2, "Gut gemacht. Du bist immer noch ein Idiot, aber ein streichelnder."),
    ]
    static let wokenByPet: [CatLine] = [
        .init(0, "Hmpf. Ich hab geschlafen."),
        .init(1, "Wer wagt es …? Ach, du."),
        .init(2, "Ernsthaft? Ich hab geschlafen, du Knalltüte."),
        .init(2, "Weck mich noch einmal und ich zieh bei dir aus."),
    ]
    static let purr: [CatLine] = [.init(0, "Schnurrr …"), .init(0, "Schnurrrrr …"), .init(0, "Prrrrr …")]
    static let nap: [CatLine] = [
        .init(0, "Ich mach mal kurz die Augen zu."),
        .init(1, "Weck mich, wenn was Spannendes passiert. Also nie."),
        .init(2, "Weck mich, wenn du was Sinnvolles machst."),
        .init(2, "Ich schlaf jetzt. Ist spannender, als dir zuzusehen."),
    ]
    static let back: [CatLine] = [
        .init(0, "Ach, auch wieder da?"),
        .init(1, "Schöne Pause gehabt? Ich nicht."),
        .init(1, "Ich hab dich vermisst. Kleiner Scherz."),
        .init(2, "Na, auch mal wieder da, du Pausenkönig?"),
        .init(2, "Oh. Du lebst noch. Schade, ich hatte schon deinen Stuhl."),
    ]
    static let wake: [CatLine] = [
        .init(0, "Ich war nie weg."),
        .init(1, "Na endlich. Hab dich vermisst. Nicht."),
        .init(2, "Da bin ich wieder. Freu dich gefälligst."),
    ]
    static let snooze: [CatLine] = [
        .init(0, "Gute Nacht."),
        .init(1, "Ich bin dann mal weg. Benimm dich."),
        .init(2, "Endlich Ruhe vor dir."),
    ]
    static let intro: [CatLine] = [
        .init(0, "Da bin ich!"),
        .init(1, "Rüdiger ist da. Ihr dürft jetzt applaudieren."),
        .init(1, "Morgen. Ich bin heute für schlechte Laune zuständig."),
        .init(2, "Da bin ich. Freu dich gefälligst."),
        .init(2, "Ich bin wieder da. Dein Tag ist hiermit offiziell ruiniert."),
    ]

    // Nachrichten vorlesen: erst der Inhalt, dann Rüdigers Senf
    static let messageComment: [CatLine] = [
        .init(0, "Schreib ruhig zurück."),
        .init(1, "Bestimmt was Unwichtiges."),
        .init(1, "Ich hätt's nicht vorgelesen. Aber gut."),
        .init(1, "Antworte bloß nicht sofort. Wirkt verzweifelt."),
        .init(1, "Wer schreibt dir denn freiwillig?"),
        .init(2, "Antworte halt, du Schnecke."),
        .init(2, "Hast du eigentlich auch Freunde, die nicht nerven?"),
        .init(2, "Lies es selbst, ich bin doch nicht dein Sekretär."),
        .init(2, "Ich hätte es gelöscht. Und den Absender gleich mit."),
    ]
    static let mailComment: [CatLine] = [
        .init(0, "Arbeit, igitt."),
        .init(1, "Ich würd sie ignorieren."),
        .init(1, "Klingt nach Arbeit. Ich bin raus."),
        .init(1, "Lass sie liegen. Die läuft nicht weg. Leider."),
        .init(2, "Noch mehr Arbeit für dich, du Sesselpupser."),
        .init(2, "Lösch sie. Vertrau mir, ich bin eine Katze."),
    ]
    static let flood: [CatLine] = [
        .init(0, "So viele Nachrichten … und mich streichelt keiner."),
        .init(1, "Na? Sind die anderen wichtiger als ich?"),
        .init(1, "Pling, pling, pling. Ich zieh aus."),
        .init(2, "Alle wollen was von dir. Ich auch, du treulose Tomate!"),
        .init(2, "Sind die anderen wichtiger als ich?! Antworte, du Verräter!"),
    ]

    static let jokes: [CatLine] = [
        .init(0, "Ich hab heute schon 14 Stunden geschlafen. Und du so?"),
        .init(0, "Ich würde dir ja helfen. Aber ich bin eine Katze."),
        .init(0, "Katzen schlafen 70 % ihres Lebens. Ich arbeite an 90."),
        .init(0, "Ich bin nicht faul. Ich bin im Energiesparmodus."),
        .init(1, "Ich hab deine To-do-Liste gesehen. Mein Beileid."),
        .init(1, "Ich hab neun Leben. Du hast diese Excel-Tabelle."),
        .init(1, "Kaffee ist keine Persönlichkeit. Bei dir fast."),
        .init(1, "Mitarbeiter des Monats? Von mir nicht."),
        .init(1, "Weißt du, was ich an Montagen mag? Nichts."),
        .init(1, "Ich liege hier rum und werde bewundert. Lern was."),
        .init(1, "Du bist mein Lieblingsmensch. Die anderen sind auch alle doof."),
        .init(1, "Ich mag dich. So wie man Regen mag: aus der Ferne."),
        .init(1, "Du hast so schöne Hände. Zum Dosenöffnen."),
        .init(1, "Ich hab dich lieb. Wie Schimmel im Kühlschrank: unerwartet."),
        .init(1, "Mach ruhig weiter. Ich beurteile dich nur ein bisschen."),
        .init(1, "Dein Passwort ist bestimmt „Passwort123“. Ich sag's keinem."),
        .init(1, "Ich hab kurz über dein Leben nachgedacht. Dann bin ich eingeschlafen."),
        .init(1, "Ich wollte was Nettes sagen. Ist mir nichts eingefallen."),
        .init(1, "Deine offenen Fenster sind wie meine Haare: überall."),
        .init(1, "Ich hab nichts gegen dich. Ich hab nur nichts für dich."),
        .init(1, "Ich bin nicht unfreundlich. Ich bin ehrlich. Ist bei dir halt dasselbe."),
        .init(1, "Lächle mal. Ach, lass es. War keine gute Idee."),
        .init(2, "Du tippst wie ein Waschbär auf Koffein."),
        .init(2, "Selbst mein Fellknäuel hat mehr Struktur als dein Schreibtisch."),
        .init(2, "Ich würd dich ja kratzen, aber du bist mir zu langweilig."),
        .init(2, "Wenn Dummheit schnurren könnte, wärst du ein Traktor."),
        .init(2, "Du bist genauso produktiv wie ich. Und ich schlafe."),
        .init(2, "Hör auf zu klicken wie ein Specht, du Dumpfbacke."),
        .init(2, "Ich hab dich lieb. Fast so sehr wie die Mäuse, die ich umbringe."),
        .init(2, "Wenn ich sterbe, erbst du nichts. Nur meine Haare. Auf deinem Pulli."),
        .init(2, "Neun Leben, und ich verschwende eins davon, dir zuzusehen."),
        .init(2, "Du bist der Grund, warum Katzen Dinge vom Tisch werfen."),
        .init(2, "Irgendwann schubs ich deinen Kaffee vom Tisch. Nicht heute. Aber irgendwann."),
        .init(2, "Ich hab deinen Lebenslauf gelesen. Ich hab gelacht."),
        .init(2, "Wenn Ahnungslosigkeit ein Beruf wäre, wärst du Chef."),
        .init(2, "Ich kratz nicht. Ich hinterlasse Bewertungen."),
        .init(2, "Dein Stuhl ist warm. Das ist das Beste an dir."),
        .init(2, "Menschen sind Dosenöffner mit Ego."),
        .init(2, "Ich hab dich gern. Als Heizung."),
        .init(2, "Ich würd ja sagen, du machst das gut. Aber ich lüge nur für Futter."),
    ]

    // Anlässe
    static let late: [CatLine] = [
        .init(0, "Es ist {time}. Geh nach Hause."),
        .init(1, "{time} Uhr. Selbst ich hab Feierabend."),
        .init(2, "Es ist {time}, du Arbeitstier. Hast du kein Zuhause?"),
        .init(2, "{time} Uhr und du bist immer noch hier. Traurig. Für uns beide."),
    ]
    static let morning: [CatLine] = [
        .init(0, "Guten Morgen!"),
        .init(1, "Morgen. Du siehst aus, wie ich mich fühle."),
        .init(2, "Morgen. Kaffee zuerst, dann reden. Oder nie."),
    ]
    static let lunch: [CatLine] = [
        .init(0, "Mittagspause! Ich hätte Thunfisch genommen."),
        .init(1, "Mittag. Iss was. Du wirst sonst noch unausstehlicher."),
        .init(2, "Mittag. Geh essen, dein Magen knurrt lauter als ich."),
    ]
    static let monday: [CatLine] = [
        .init(0, "Montag. Ich bin dagegen."),
        .init(1, "Montag. Ich hab mich schon beschwert, du musst nicht mehr."),
        .init(2, "Montagmorgen, und du siehst aus wie ich nach dem Tierarzt."),
    ]
    static let friday: [CatLine] = [
        .init(0, "Freitag! Fast geschafft."),
        .init(1, "Freitagnachmittag. Tu wenigstens so, als würdest du arbeiten."),
        .init(2, "Freitag. Mach Schluss, du Sesselpupser."),
    ]
    static let weekend: [CatLine] = [
        .init(0, "Wochenende und du arbeitest? Mach Pause."),
        .init(1, "Es ist Wochenende. Selbst die Maus hat frei."),
        .init(2, "Wochenende und du sitzt hier. Kein Wunder, dass du keine Freunde hast."),
    ]
    static let mailPile: [CatLine] = [
        .init(0, "{n} ungelesene Mails. Nur so als Info."),
        .init(1, "{n} ungelesene Mails. Ich hätte da noch einen Platz im Katzenkorb frei."),
        .init(2, "{n} ungelesene Mails, du Chaot. Respekt."),
    ]
    static let shelfFull: [CatLine] = [
        .init(0, "Dein Ablagefach ist ganz schön voll."),
        .init(1, "Dein Ablagefach quillt über. Wie mein Katzenklo."),
        .init(2, "Räum mal dein Ablagefach auf, du Messie."),
    ]
    static let pause: [CatLine] = [
        .init(0, "Du sitzt schon lange. Steh mal kurz auf."),
        .init(0, "Pause! Wasser trinken, strecken, so wie ich."),
        .init(1, "Steh mal auf, du Bürostuhl-Statue."),
        .init(1, "Streck dich mal. Du siehst schon aus wie ein Fragezeichen."),
        .init(2, "Beweg dich mal, bevor du am Stuhl festwächst, du Kartoffel."),
    ]
    static let treat: [CatLine] = [
        .init(0, "Mjam! Danke!"),
        .init(1, "Mjam. Bestechung funktioniert."),
        .init(1, "Lecker. Du darfst bleiben."),
        .init(2, "Mjam. Das war's? Geizhals."),
        .init(2, "Ein Leckerli. Wow. Willst du einen Orden?"),
    ]
    static let treatTooMuch: [CatLine] = [
        .init(0, "Ich bin satt. Wirklich."),
        .init(1, "Willst du mich mästen?"),
        .init(2, "Noch ein Leckerli und ich pass nicht mehr in mein Fenster, du Futterdealer."),
    ]
    static let fileDrop: [CatLine] = [
        .init(0, "Igitt, Arbeit."),
        .init(1, "Nimm das weg. Ich bin nicht zuständig."),
        .init(1, "Sieht aus wie Arbeit. Ich hab Allergie dagegen."),
        .init(2, "Was soll ich damit? Drauf schlafen? Ok, gib her. Nein. Doch nicht."),
        .init(2, "Leg mir das nochmal hin und ich markier dein Revier."),
    ]
}
