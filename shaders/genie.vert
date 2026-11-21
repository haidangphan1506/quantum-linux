#version 440
// Efecto «genio» de macOS (modules/effects/GenieFx.qml), sobre una malla (GridMesh).
// La ventana se deforma en un embudo hacia el icono del dock:
//   curve: los lados se doblan en S (arriba ancho de la ventana, en el dock ancho del icono)
//   slide: el contenido baja por el embudo; lo más cercano al dock entra primero y se aplasta ahí
// Todo en coordenadas de la pantalla (el ShaderEffect ocupa la pantalla entera).
// Compilar: /usr/lib/qt6/bin/qsb --qt6 -o genie.vert.qsb genie.vert
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float axis;    // 0: dock abajo/arriba (eje y) | 1: dock a la izquierda/derecha (eje x)
    float a0;      // borde de la ventana en la coordenada 0 de la textura, sobre el eje
    float a1;      // borde en la coordenada 1
    float farA;    // el borde más lejano del dock (a0 o a1)
    float dockA;   // el dock sobre el eje
    float l0;      // bordes transversales de la ventana
    float r0;
    float ld;      // bordes transversales en el dock (ancho del icono)
    float rd;
    float curve;   // 0..1
    float slide;   // 0..1
};

out gl_PerVertex { vec4 gl_Position; };

void main() {
    vec2 tc = qt_MultiTexCoord0;
    qt_TexCoord0 = tc;
    float along = axis < 0.5 ? tc.y : tc.x;
    float across = axis < 0.5 ? tc.x : tc.y;

    float span = dockA - farA;
    float dir = span >= 0.0 ? 1.0 : -1.0;
    // posición sobre el eje: la ventana se corre hacia el dock y se queda «atascada» en él
    float a = mix(a0, a1, along) + slide * span;
    a = dir > 0.0 ? min(a, dockA) : max(a, dockA);

    // embudo: cuánto se estrecha según lo cerca que está del dock (curva en S, como macOS)
    float u = clamp((a - farA) / (abs(span) < 1.0 ? dir : span), 0.0, 1.0);
    float s = curve * smoothstep(0.0, 1.0, u);
    float l = mix(l0, ld, s);
    float r = mix(r0, rd, s);
    float c = mix(l, r, across);

    vec2 pos = axis < 0.5 ? vec2(c, a) : vec2(a, c);
    gl_Position = qt_Matrix * vec4(pos, 0.0, 1.0);
}
