/* jyinject —— 用 /dev/uinput 造一个虚拟键盘，按脚本注入按键，用于真机验证按键链路
 * 用法: ./jyinject <等待秒数> <键名[,键名...]>
 * 键名: up down left right esc enter space tab shift alt a b
 */
#include <linux/uinput.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static int g_fd = -1;

static void emit(int type, int code, int val)
{
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type;
    ev.code = code;
    ev.value = val;
    if (write(g_fd, &ev, sizeof(ev)) < 0)
    { perror("write"); }
}

static void press(int code)
{
    emit(EV_KEY, code, 1);
    emit(EV_SYN, SYN_REPORT, 0);
    usleep(120000);
    emit(EV_KEY, code, 0);
    emit(EV_SYN, SYN_REPORT, 0);
    usleep(180000);
}

static int name2code(const char* n)
{
    if (!strcmp(n, "up")) return KEY_UP;
    if (!strcmp(n, "down")) return KEY_DOWN;
    if (!strcmp(n, "left")) return KEY_LEFT;
    if (!strcmp(n, "right")) return KEY_RIGHT;
    if (!strcmp(n, "esc")) return KEY_ESC;
    if (!strcmp(n, "enter")) return KEY_ENTER;
    if (!strcmp(n, "space")) return KEY_SPACE;
    if (!strcmp(n, "tab")) return KEY_TAB;
    if (!strcmp(n, "shift")) return KEY_LEFTSHIFT;
    if (!strcmp(n, "alt")) return KEY_LEFTALT;
    if (!strcmp(n, "a")) return KEY_A;
    if (!strcmp(n, "b")) return KEY_B;
    if (!strcmp(n, "e")) return KEY_E;
    if (!strcmp(n, "t")) return KEY_T;
    return -1;
}

int main(int argc, char** argv)
{
    struct uinput_setup setup;
    char buf[256];
    char* tok;
    char* save;
    int delay = 8;

    if (argc < 3)
    {
        fprintf(stderr, "usage: %s <delay_sec> <key,key,...>\n", argv[0]);
        return 2;
    }
    delay = atoi(argv[1]);

    g_fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (g_fd < 0)
    {
        perror("open /dev/uinput");
        return 1;
    }

    ioctl(g_fd, UI_SET_EVBIT, EV_KEY);
    ioctl(g_fd, UI_SET_EVBIT, EV_SYN);
    for (int k = 1; k < 128; k++)
    { ioctl(g_fd, UI_SET_KEYBIT, k); }

    memset(&setup, 0, sizeof(setup));
    setup.id.bustype = BUS_USB;
    setup.id.vendor = 0x1234;
    setup.id.product = 0x5678;
    snprintf(setup.name, UINPUT_MAX_NAME_SIZE, "jy-test-kbd");
    if (ioctl(g_fd, UI_DEV_SETUP, &setup) < 0)
    { perror("UI_DEV_SETUP"); return 1; }
    if (ioctl(g_fd, UI_DEV_CREATE) < 0)
    { perror("UI_DEV_CREATE"); return 1; }

    fprintf(stderr, "virt kbd created, waiting %d s\n", delay);
    fflush(stderr);
    sleep(delay);

    strcpy(buf, argv[2]);
    save = buf;
    tok = strtok_r(save, ",", &save);
    while (tok != NULL)
    {
        if (tok[0] == 'w')
        {
            int sec = atoi(tok + 1);
            fprintf(stderr, "wait %d s\n", sec);
            fflush(stderr);
            sleep(sec > 0 ? sec : 1);
        }
        else
        {
            int code = name2code(tok);
            fprintf(stderr, "press %s -> %d\n", tok, code);
            fflush(stderr);
            if (code > 0) { press(code); }
        }
        tok = strtok_r(NULL, ",", &save);
    }

    ioctl(g_fd, UI_DEV_DESTROY);
    close(g_fd);
    fprintf(stderr, "done\n");
    return 0;
}
