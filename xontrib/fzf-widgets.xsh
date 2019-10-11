import os
import re
import subprocess
from xonsh.history.main import history_main
from xonsh.completers.path import complete_path
from xonsh.platform import ptk_shell_type
from prompt_toolkit.keys import Keys

def get_fzf_binary_name():
    if 'TMUX' in ${...}:
        return 'fzf-tmux'
    return 'fzf'


def get_fzf_binary_path():
    path = $(which @(get_fzf_binary_name()))
    if not path:
        raise Exception("Could not determine path of fzf using `which`; maybe it is not installed or not on PATH?")
    return path


def fzf_insert_history(event):
    # Run fzf, feeding it the xonsh history
    # fzf prints the user's choice on stdout.

    # universal_newlines=True is used because `history_main` writes str()s
    # That also means that we don't have to `decode()` the stdout.read()` below.
    proc = subprocess.Popen([get_fzf_binary_path(), '--read0', '--tac', '--no-sort', '--tiebreak=index', '+m', '--reverse', '--height=40%', f'-q ^{event.current_buffer.text}'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, universal_newlines=True)
    history_main(args=['show', '-0', 'all'], stdout=proc.stdin)
    proc.stdin.close()
    proc.wait()
    choice = proc.stdout.read().strip()

    # Redraw the shell because fzf used alternate mode
    event.cli.renderer.erase()

    if choice:
        event.current_buffer.insert_text(choice)


def fzf_insert_file(event):
    before_cursor = event.current_buffer.document.current_line_before_cursor
    delim_pos = before_cursor.rfind(' ', 0, len(before_cursor))
    prefix = None
    if delim_pos != -1 and delim_pos != len(before_cursor) - 1:
        prefix = before_cursor[delim_pos+1:]

    cwd = None
    path = ''
    if prefix:
        paths = complete_path(os.path.normpath(prefix), before_cursor, 0, len(before_cursor), None)[0]
        if len(paths) == 1:
            path = paths.pop()
            expanded_path = os.path.expanduser(path)
            if os.path.isdir(expanded_path):
                cwd = os.getcwd()
                os.chdir(expanded_path)

    env = os.environ
    if 'fzf_find_command' in ${...}:
        env['FZF_DEFAULT_COMMAND'] = $fzf_find_command
    if 'FZF_DEFAULT_OPTS' in ${...}:
        env['FZF_DEFAULT_OPTS'] = $FZF_DEFAULT_OPTS
    choice = subprocess.run([get_fzf_binary_path(), '-m', '--reverse', '--height=40%'], stdout=subprocess.PIPE, universal_newlines=True, env=env).stdout.strip()

    if cwd:
        os.chdir(cwd)

    event.cli.renderer.erase()

    if choice:
        if path:
            event.current_buffer.delete_before_cursor(len(prefix))

        command = ''
        for c in choice.splitlines():
            command += "'" + os.path.join(path, c.strip()) + "' "

        event.current_buffer.insert_text(command.strip())


def fzf_prompt_from_string(string):
    choice = subprocess.run([get_fzf_binary_path(), '--tiebreak=index', '+m', '--reverse', '--height=40%'], input=string, stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
    return choice


@events.on_ptk_create
def custom_keybindings(bindings, **kw):
    def handler(key_name):
        def do_nothing(func):
            pass

        if ptk_shell_type() == 'prompt_toolkit2':
            binder = bindings.add
        else:
            binder = bindings.registry.add_binding

        key = ${...}.get(key_name)
        if key:
            return binder(key)
        return do_nothing

    @handler('fzf_history_binding')
    def fzf_history(event):
        fzf_insert_history(event)

    @handler('fzf_ssh_binding')
    def fzf_ssh(event):
        items = re.sub(r'(?i)host ', '', $(cat ~/.ssh/config /etc/ssh/ssh_config | grep -i '^host'))
        choice = fzf_prompt_from_string(items)

        # Redraw the shell because fzf used alternate mode
        event.cli.renderer.erase()

        if choice:
            event.current_buffer.insert_text('ssh ' + choice)

    @handler('fzf_file_binding')
    def fzf_file(event):
        fzf_insert_file(event)
