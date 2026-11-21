#version 440
// Efecto «genio»: solo dibuja la captura de la ventana (la forma la hace genie.vert).
// Compilar: /usr/lib/qt6/bin/qsb --qt6 -o genie.frag.qsb genie.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float axis;
    float a0;
    float a1;
    float farA;
    float dockA;
    float l0;
    float r0;
    float ld;
    float rd;
    float curve;
    float slide;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    fragColor = texture(source, qt_TexCoord0) * qt_Opacity;
}
