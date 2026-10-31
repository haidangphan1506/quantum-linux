pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Clima para la pantalla de bloqueo (Open-Meteo: gratis y sin cuenta).
// La ubicación sale de la IP (aproximada) o de la ciudad escrita en Personalizar.
// Solo se consulta cuando se pide (al bloquear) y como mucho cada 30 minutos.
Singleton {
    id: root

    property bool ready: false
    property real temp: 0
    property real feels: 0
    property real high: 0
    property real low: 0
    property int code: 0
    property bool day: true
    property double updated: 0

    readonly property string text: describe(code)
    readonly property string icon: iconFor(code, day)

    // Códigos WMO → texto en español
    function describe(c: int): string {
        if (c === 0) return "Despejado";
        if (c <= 2) return "Parcialmente nublado";
        if (c === 3) return "Nublado";
        if (c <= 48) return "Niebla";
        if (c <= 57) return "Llovizna";
        if (c <= 67) return "Lluvia";
        if (c <= 77) return "Nieve";
        if (c <= 82) return "Chubascos";
        if (c <= 86) return "Nevadas";
        return "Tormenta";
    }
    function iconFor(c: int, isDay: bool): string {
        if (c === 0) return isDay ? "clear_day" : "clear_night";
        if (c <= 2) return isDay ? "partly_cloudy_day" : "partly_cloudy_night";
        if (c === 3) return "cloud";
        if (c <= 48) return "foggy";
        if (c <= 67) return "rainy";
        if (c <= 77) return "weather_snowy";
        if (c <= 82) return "rainy";
        if (c <= 86) return "weather_snowy";
        return "thunderstorm";
    }

    function refresh(): void {
        if (Quickshell.env("QUANTUM_DEMO_WEATHER")) {
            // datos de ejemplo para capturas (sin consultar la ubicación real)
            const d = Quickshell.env("QUANTUM_DEMO_WEATHER").split(",").map(Number);
            temp = d[0]; feels = d[1]; high = d[2]; low = d[3]; code = d[4]; day = true;
            ready = true;
            return;
        }
        if (Date.now() - updated < 30 * 60 * 1000 || proc.running)
            return;
        proc.running = true;
    }

    // Ubicación (ciudad elegida o por IP) y luego el pronóstico, en un solo paso
    Process {
        id: proc
        command: ["sh", "-c",
            "city=\"$1\"; " +
            "if [ -n \"$city\" ]; then " +
            "  loc=$(curl -sf -m 10 --get --data-urlencode \"name=$city\" -d count=1 -d language=es https://geocoding-api.open-meteo.com/v1/search) || exit 1; " +
            "  lat=$(printf '%s' \"$loc\" | grep -o '\"latitude\":[-0-9.]*' | head -1 | cut -d: -f2); " +
            "  lon=$(printf '%s' \"$loc\" | grep -o '\"longitude\":[-0-9.]*' | head -1 | cut -d: -f2); " +
            "else " +
            "  loc=$(curl -sf -m 10 https://ipapi.co/json/ || curl -sf -m 10 https://ipwho.is/) || exit 1; " +
            "  lat=$(printf '%s' \"$loc\" | grep -o '\"latitude\": *[-0-9.]*' | head -1 | grep -o '[-0-9.]*$'); " +
            "  lon=$(printf '%s' \"$loc\" | grep -o '\"longitude\": *[-0-9.]*' | head -1 | grep -o '[-0-9.]*$'); " +
            "fi; [ -n \"$lat\" ] && [ -n \"$lon\" ] || exit 1; " +
            // la luz nocturna «al atardecer» (quantum-display) usa esta ubicación
            "mkdir -p \"$2\" && printf '%s %s\\n' \"$lat\" \"$lon\" > \"$2/location\"; " +
            "curl -sf -m 10 \"https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
            "&current=temperature_2m,apparent_temperature,weather_code,is_day" +
            "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1\"",
            "sh", Settings.lock.city, Theme.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    root.temp = j.current.temperature_2m;
                    root.feels = j.current.apparent_temperature;
                    root.code = j.current.weather_code;
                    root.day = j.current.is_day === 1;
                    root.high = j.daily.temperature_2m_max[0];
                    root.low = j.daily.temperature_2m_min[0];
                    root.updated = Date.now();
                    root.ready = true;
                } catch (e) {
                    console.warn("Weather: respuesta inválida");
                }
            }
        }
    }
}
