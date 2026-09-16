import re
import unittest
from copy import deepcopy
from pathlib import Path
from xml.etree import ElementTree as ET


XML = Path(__file__).resolve().parents[1] / 'xml'
SEARCH = ET.parse(XML / 'Includes_Search.xml').getroot()
HOME = ET.parse(XML / 'Home.xml').getroot()
INCLUDES = {node.get('name'): node for node in SEARCH.findall('include')}
EXPRESSIONS = {node.get('name'): node.text for node in SEARCH.findall('expression')}


def expand(node):
    node = deepcopy(node)
    for child in list(node):
        if child.tag == 'include':
            name = child.get('content') or child.text
            if name not in INCLUDES:
                continue
            template = INCLUDES[name]
            body = template.find('definition')
            if body is None:
                body = template
            index = list(node).index(child)
            for value in body:
                if value.tag != 'param':
                    node.insert(index, expand(value))
                    index += 1
            node.remove(child)
        else:
            index = list(node).index(child)
            node.remove(child)
            node.insert(index, expand(child))
    return node


KEYBOARD = expand(INCLUDES['NaraSearchKeyboard'])
CONTROLS = {int(node.get('id')): node for node in SEARCH.iter('control') if node.get('id')}
CONTROLS.update({int(node.get('id')): node for node in KEYBOARD.iter('control') if node.get('id')})
CONTROLS[9011] = HOME.find('.//control[@id="9011"]')
KEYBOARD_IDS = set(int(node.get('id')) for node in KEYBOARD.iter('control') if node.get('id'))


class Navigation:
    def __init__(self, query='', movies=0, tvshows=0, **properties):
        self.query = query
        self.counts = {16101: movies, 16102: tvshows}
        self.properties = {'Home.Section': 'search', **properties}
        self.focused = 9011
        self.modal = False
        self.positions = {16992: 0, 16994: 0, 16101: 0, 16102: 0}
        self.input_actions = []

    def evaluate(self, condition):
        for _ in range(10):
            if '$EXP[' not in condition:
                break
            condition = re.sub(r'\$EXP\[([^]]+)\]', lambda m: '[' + EXPRESSIONS[m[1]] + ']', condition)
        condition = condition.replace('String.IsEmpty(Control.GetLabel(16999).index(1))', str(not self.query))
        condition = re.sub(r'String.IsEmpty\(Window\(home\).Property\(([^)]+)\)\)',
                           lambda m: str(not self.properties.get(m[1])), condition)
        condition = re.sub(r'String.IsEqual\(Window\(home\).Property\(([^)]+)\),([^)]*)\)',
                           lambda m: str(self.properties.get(m[1], '') == m[2]), condition)
        condition = re.sub(r'Integer.Is(Greater|Equal)\(Container\((\d+)\).NumItems,(\d+)\)',
                           lambda m: str(self.counts[int(m[2])] > int(m[3]) if m[1] == 'Greater'
                                         else self.counts[int(m[2])] == int(m[3])), condition)
        condition = condition.replace('ControlGroup(16010).HasFocus()', str(self.focused in KEYBOARD_IDS))
        condition = condition.replace('System.HasActiveModalDialog', str(self.modal))
        condition = condition.replace('!', ' not ').replace('+', ' and ').replace('|', ' or ')
        condition = condition.replace('[', '(').replace(']', ')')
        if re.sub(r'True|False|\band\b|\bor\b|\bnot\b|[()\s]', '', condition):
            raise ValueError('Unsupported condition: ' + condition)
        return eval(condition, {'__builtins__': {}}, {})

    def hidden(self):
        return self.evaluate('$EXP[NaraSearchKeyboardHidden]')

    def focus(self, control_id):
        if control_id == 9000:
            control_id = 9011
        if control_id not in CONTROLS:
            raise AssertionError(f'Missing focus target: {control_id}')
        if control_id in self.counts:
            assert self.query and self.counts[control_id] > 0, 'Focus entered an empty result list'
        self.focused = control_id
        self.actions(CONTROLS[control_id], 'onfocus')

    def actions(self, node, event):
        # CGUIAction selects executable conditions before running their side effects.
        selected = [child.text for child in node.findall(event)
                    if self.evaluate(child.get('condition', 'True')) and not child.text.isdigit()]
        for action in selected:
            if match := re.fullmatch(r'SetProperty\(([^,]+),([^,]+),home\)', action):
                self.properties[match[1]] = match[2]
            elif match := re.fullmatch(r'ClearProperty\(([^,]+),home\)', action):
                self.properties.pop(match[1], None)
            elif match := re.fullmatch(r'SetFocus\((\d+)\)', action):
                self.focus(int(match[1]))
            elif action.startswith('Number') or action == 'Backspace':
                assert self.focused == 16999, 'Input bypassed the hidden edit'
                self.input_actions.append(action)
            elif action != 'noop':
                raise ValueError('Unsupported action: ' + action)

    def route(self, node, event):
        self.actions(node, event)
        # OnMove needs a native target to consume Back after executing side effects.
        for child in node.findall(event):
            if child.text.isdigit() and self.evaluate(child.get('condition', 'True')):
                target = int(child.text)
                if target == self.focused:
                    return False
                self.focus(target)
                return True
        return False

    def press(self, direction):
        node = CONTROLS[self.focused]
        if self.focused in (16992, 16994) and direction != 'back':
            layout = node.find('itemlayout')
            columns = int(node.findtext('width')) // int(layout.get('width'))
            count = len(node.findall('content/item'))
            index = self.positions[self.focused]
            row, column = divmod(index, columns)
            if direction in ('left', 'right'):
                assert node.findtext('on' + direction) == str(self.focused)
                delta = -1 if direction == 'left' else 1
                self.positions[self.focused] = row * columns + (column + delta) % columns
                return True
            if direction == 'up' and row > 0:
                self.positions[self.focused] -= columns
                return True
            if direction == 'down' and index + columns < count:
                self.positions[self.focused] += columns
                return True
        return self.route(node, 'on' + direction)

    def click_key(self, index):
        self.positions[self.focused] = index
        self.actions(CONTROLS[self.focused].findall('content/item')[index], 'onclick')


class SearchDrawerTests(unittest.TestCase):
    def test_first_empty_visit_opens_without_stealing_navigation_focus(self):
        n = Navigation(**{'Home.Section': 'movies', 'Search.KeyboardHidden': 'true'})
        self.assertTrue(n.hidden())
        n.focus(9011)
        self.assertFalse(n.hidden())
        self.assertEqual(n.focused, 9011)
        self.assertTrue(n.press('down'))
        self.assertEqual(n.focused, 16992)

    def test_results_down_and_back_preserve_query_type_and_selection(self):
        for active, target in (('movies', 16101), ('tvshows', 16102)):
            with self.subTest(active=active):
                n = Navigation('ABC', 12, 7, **{'Home.Section': 'movies', 'Search.ActiveType': active})
                n.positions.update({target: 4, 16992: 19})
                n.focus(9011)
                self.assertTrue(n.hidden())
                self.assertTrue(n.press('down'))
                self.assertEqual(n.focused, target)
                self.assertTrue(n.press('down'))
                self.assertFalse(n.hidden())
                self.assertEqual(n.positions[16992], 19)
                self.assertTrue(n.press('back'))
                self.assertTrue(n.hidden())
                self.assertEqual(n.focused, target)
                self.assertEqual(n.positions[target], 4)
                self.assertEqual(n.query, 'ABC')
                self.assertEqual(n.properties['Search.ActiveType'], active)

    def test_no_result_back_is_consumed_and_stays_closed_at_navigation(self):
        for query, count in (('', 0), ('ZZ', 0), ('', 5)):
            with self.subTest(query=query, count=count):
                n = Navigation(query, count)
                n.focus(9011)
                n.focus(16992)
                self.assertTrue(n.press('back'))
                self.assertEqual(n.focused, 9011)
                self.assertTrue(n.hidden())
                self.assertEqual(n.query, query)
                self.assertTrue(n.press('down'))
                self.assertEqual(n.focused, 16992)
                self.assertFalse(n.hidden())

    def test_two_letter_rows_wrap_horizontally_and_keep_columns(self):
        n = Navigation()
        n.focus(16992)
        for index in range(14):
            n.positions[16992] = index
            self.assertTrue(n.press('down'))
            self.assertEqual(n.positions[16992], index + 14)
            self.assertTrue(n.press('up'))
            self.assertEqual(n.positions[16992], index)
        n.positions[16992] = 0
        n.press('left')
        self.assertEqual(n.positions[16992], 13)
        n.press('right')
        self.assertEqual(n.positions[16992], 0)
        n.press('up')
        self.assertEqual(n.focused, 16998)
        self.assertTrue(n.press('up'))
        self.assertEqual(n.focused, 9011)
        self.assertTrue(n.hidden())

    def test_number_toggle_focuses_immediately_and_closes_without_reopening(self):
        n = Navigation('AB', 2)
        n.focus(16992)
        n.click_key(26)
        self.assertEqual(n.focused, 16994)
        self.assertTrue(n.properties.get('Search.NumbersVisible'))
        visible = CONTROLS[16994].find('visible')
        self.assertEqual(visible.get('allowhiddenfocus'), 'true')
        n.press('up')
        self.assertEqual(n.focused, 16992)
        self.assertEqual(n.positions[16992], 26)
        n.click_key(26)
        self.assertNotIn('Search.NumbersVisible', n.properties)
        self.assertEqual(n.focused, 16992)

    def test_back_from_digits_closes_entire_drawer_and_returns_to_results(self):
        n = Navigation('AB', 0, 3)
        n.focus(16992)
        n.click_key(26)
        self.assertTrue(n.press('back'))
        self.assertEqual(n.focused, 16102)
        self.assertTrue(n.hidden())
        self.assertNotIn('Search.NumbersVisible', n.properties)

    def test_virtual_input_restores_the_selected_key(self):
        n = Navigation('AB', 3)
        n.focus(16992)
        for index in list(range(26)) + [27]:
            n.click_key(index)
            self.assertEqual(n.focused, 16992)
            self.assertEqual(n.positions[16992], index)
            self.assertFalse(n.hidden())
        n.click_key(26)
        for index in range(10):
            n.click_key(index)
            self.assertEqual(n.focused, 16994)
            self.assertEqual(n.positions[16994], index)
            self.assertFalse(n.hidden())
        self.assertIn('Backspace', n.input_actions)
        self.assertTrue(all('Number' + str(digit) in n.input_actions for digit in range(10)))

    def test_asynchronous_results_do_not_close_or_move_keyboard_focus(self):
        for first, expected in ((16101, 16101), (16102, 16102)):
            n = Navigation('AB')
            n.focus(16992)
            n.counts[first] = 3
            self.assertFalse(n.hidden())
            self.assertEqual(n.focused, 16992)
            self.assertTrue(n.press('back'))
            self.assertEqual(n.focused, expected)
        n = Navigation('AB', 0, 3, **{'Search.ActiveType': 'tvshows'})
        n.focus(16992)
        n.counts[16101] = 7
        n.press('back')
        self.assertEqual(n.focused, 16102)

    def test_modal_suppression_preserves_the_previous_drawer_state(self):
        for focus in (16992, 16994, 16101):
            n = Navigation('AB', 4, **{'Search.NumbersVisible': 'true'})
            n.focus(focus)
            hidden = n.hidden()
            properties = dict(n.properties)
            n.modal = True
            self.assertTrue(n.hidden())
            n.modal = False
            self.assertEqual(n.hidden(), hidden)
            self.assertEqual(n.focused, focus)
            self.assertEqual(n.properties, properties)

    def test_layout_reserves_digits_and_keeps_results_above_drawer(self):
        letters = CONTROLS[16992]
        digits = CONTROLS[16994]
        drawer = CONTROLS[16010]
        height = int(drawer.findtext('height'))
        self.assertEqual(letters.findtext('centerleft'), '50%')
        self.assertEqual(digits.findtext('centerleft'), '50%')
        self.assertEqual(len(letters.findall('content/item')), 28)
        self.assertEqual(int(letters.findtext('width')) // int(letters.find('itemlayout').get('width')), 14)
        self.assertEqual(int(letters.findtext('height')) // int(letters.find('itemlayout').get('height')), 2)
        self.assertLess(int(letters.findtext('top')) + int(letters.findtext('height')), int(digits.findtext('top')))
        self.assertLessEqual(int(digits.findtext('top')) + int(digits.findtext('height')), height - 24)
        self.assertEqual(drawer.findtext('bottom'), '0')
        self.assertEqual(drawer.find('control/texture').get('glassstyle'), 'regular')
        self.assertEqual(drawer.find('control/texture').get('glassedge'), 'soft')
        lift = int(INCLUDES['NaraSearchResultsLift'].find('animation').get('end').split(',')[1])
        for id in (16101, 16102):
            row = CONTROLS[id]
            self.assertLessEqual(int(row.findtext('top')) + lift + int(row.findtext('height')), 1080 - height)


if __name__ == '__main__':
    unittest.main()
