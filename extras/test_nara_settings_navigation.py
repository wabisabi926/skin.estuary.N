import re
import unittest
from pathlib import Path
from xml.etree import ElementTree


HOME_XML = Path(__file__).resolve().parents[1] / 'xml' / 'Home.xml'


def evaluate(condition, state):
    condition = re.sub(
        r'String.IsEqual\(Window\(home\).Property\((Home.Section|Home.FileReturnControl)\),([^)]*)\)',
        lambda m: str(state.get(m[1], '') == m[2]), condition)
    condition = re.sub(
        r'String.IsEmpty\(Window\(home\).Property\((Home.Section|Home.FileReturnControl)\)\)',
        lambda m: str(not state.get(m[1], '')), condition)
    condition = re.sub(r'Window.(Next|Previous)\(([^)]+)\)',
                       lambda m: str(state.get(m[1]) == m[2]), condition)
    condition = re.sub(r'Control.HasFocus\((\d+)\)',
                       lambda m: str(state['focus'] == int(m[1])), condition)
    condition = condition.replace('Skin.HasSetting(HomeMenuNoMovieButton)', 'False')
    condition = condition.replace('!', ' not ').replace('+', ' and ').replace('|', ' or ')
    if re.sub(r'True|False|\band\b|\bor\b|\bnot\b|[()\s]', '', condition):
        raise ValueError(f'Unsupported condition: {condition}')
    return eval(condition, {'__builtins__': {}}, {})


def run_home_actions(root, event, state):
    # Kodi evaluates all action conditions before it executes the selected actions.
    actions = []
    for node in root.findall(event):
        action = node.text or ''
        if 'Home.FileReturnControl' not in action and not action.startswith(
                ('SetFocus(', 'SetProperty(Home.Section,')):
            continue
        if evaluate(node.get('condition', 'True'), state):
            actions.append(action)
    for action in actions:
        if match := re.fullmatch(r'SetFocus\((\d+)\)', action):
            state['focus'] = int(match[1])
        elif match := re.fullmatch(r'SetProperty\(([^,]+),([^,]+),home\)', action, re.I):
            state[match[1]] = match[2]
        elif match := re.fullmatch(r'ClearProperty\(([^,]+),home\)', action, re.I):
            state.pop(match[1], None)
        else:
            raise ValueError(f'Unsupported action: {action}')


class HomeFileReturnTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ElementTree.parse(HOME_XML).getroot()

    def round_trip(self, state):
        state['Next'] = 'filemanager'
        run_home_actions(self.root, 'onunload', state)
        state['Previous'] = 'filemanager'
        run_home_actions(self.root, 'onload', state)

    def test_file_entries_restore_the_actual_launch_focus(self):
        for focus in (15010, 15020, 9017):
            with self.subTest(focus=focus):
                state = {'Home.Section': 'files', 'focus': focus, 'Next': 'filemanager',
                         'Home.FileReturnControl': '15020'}
                run_home_actions(self.root, 'onunload', state)
                self.assertEqual(state.get('Home.FileReturnControl'), str(focus))
                state.update(focus=9000, Previous='filemanager')
                run_home_actions(self.root, 'onload', state)
                self.assertEqual(state['focus'], focus)
                self.assertEqual(state['Home.Section'], 'files')
                self.assertNotIn('Home.FileReturnControl', state)

    def test_settings_shortcut_preserves_the_original_section_and_menu_focus(self):
        for section in ('search', 'movies', 'tvshows', 'favorites', 'files', 'music', 'livetv'):
            for stale_focus in ('15010', '15020', '9017'):
                with self.subTest(section=section, stale_focus=stale_focus):
                    state = {'Home.Section': section, 'focus': 804,
                             'Home.FileReturnControl': stale_focus}
                    self.round_trip(state)
                    self.assertEqual(state['Home.Section'], section)
                    self.assertEqual(state['focus'], 804)
                    self.assertNotIn('Home.FileReturnControl', state)

    def test_other_destinations_do_not_retain_a_file_return_target(self):
        state = {'Home.Section': 'files', 'focus': 15010, 'Next': 'playersettings',
                 'Home.FileReturnControl': '15020'}
        run_home_actions(self.root, 'onunload', state)
        self.assertNotIn('Home.FileReturnControl', state)

    def test_stale_file_marker_does_not_force_a_different_section(self):
        state = {'Home.Section': 'movies', 'focus': 804, 'Previous': 'filemanager',
                 'Home.FileReturnControl': '15010'}
        run_home_actions(self.root, 'onload', state)
        self.assertEqual(state['Home.Section'], 'movies')
        self.assertEqual(state['focus'], 804)


if __name__ == '__main__':
    unittest.main()
