import re
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET


XML = Path(__file__).resolve().parents[1] / 'xml'
ANIMATIONS = ET.parse(XML / 'Includes_Animations.xml').getroot()
HOME = ET.parse(XML / 'Includes_Home.xml').getroot()
INFO = ET.parse(XML / 'DialogVideoInfo.xml').getroot()
EXPRESSIONS = {node.get('name'): node.text for node in HOME.findall('expression')}
SOURCE = ANIMATIONS.find('variable[@name="NaraVideoInfoFanartSourceVar"]')
CAMERA = ANIMATIONS.find('include[@name="Animation_NaraFanartDetail"]/definition/animation')
FOLLOW = INFO.findall('.//control[@id="5900"]/animation[@source]')


def window_id(value):
    return {'home': '10000', 'videos': '10025', 'movieinformation': '12003'}.get(
        value.lower(), value)


class DialogStack:
    def __init__(self, page='home', section='search'):
        self.visible = {window_id(page)}
        self.properties = {('10000', 'Home.Section'): section}
        self.no_fanart = False
        self.video = False

    def evaluate(self, condition, context='12003'):
        condition = re.sub(r'\$EXP\[([^]]+)\]',
                           lambda m: '[' + EXPRESSIONS[m[1]] + ']', condition)
        condition = re.sub(
            r'String.IsEqual\(Window(?:\(([^)]+)\))?\.Property\(([^)]+)\),([^)]*)\)',
            lambda m: str(self.properties.get((window_id(m[1] or context), m[2]), '') == m[3]),
            condition)
        condition = re.sub(r'Window.IsVisible\(([^)]+)\)',
                           lambda m: str(window_id(m[1]) in self.visible), condition)
        condition = condition.replace('Skin.HasSetting(no_fanart)', str(self.no_fanart))
        condition = condition.replace('Player.HasVideo', str(self.video))
        condition = re.sub(r'\btrue\b', 'True', condition)
        condition = condition.replace('!', ' not ').replace('+', ' and ').replace('|', ' or ')
        condition = condition.replace('[', '(').replace(']', ')')
        if re.sub(r'True|False|\band\b|\bor\b|\bnot\b|[()\s]', '', condition):
            raise ValueError('Unsupported condition: ' + condition)
        return eval(condition, {'__builtins__': {}}, {})

    def open_info(self, dialog='12003'):
        self.visible.add(dialog)
        source = next(value.text for value in SOURCE
                      if self.evaluate(value.get('condition', 'true'), dialog))
        self.properties[(dialog, 'VideoInfo.FanartSource')] = source
        return source

    def camera_active(self, source):
        condition = CAMERA.get('condition').replace('$PARAM[source]', source)
        condition = condition.replace('$PARAM[enabled]', '!Player.HasVideo' if source == 'library' else 'true')
        return self.evaluate(condition)

    def follow(self, dialog='12003'):
        return [(node.get('sourcewindow'), node.get('source')) for node in FOLLOW
                if self.evaluate(node.get('condition'), dialog)]


class FanartTransitionsTest(unittest.TestCase):
    def test_search_only_zooms_for_detail_and_holds_through_closing_fade(self):
        stack = DialogStack()
        self.assertFalse(stack.camera_active('search'))
        self.assertEqual(stack.open_info(), 'search')
        self.assertEqual(stack.follow(), [('10000', '16590')])
        self.assertTrue(stack.camera_active('search'))
        # A closing dialog remains visible until its exit animation completes.
        self.assertIn('12003', stack.visible)
        self.assertTrue(stack.camera_active('search'))
        stack.visible.remove('12003')
        self.assertFalse(stack.camera_active('search'))
        stack.open_info()
        self.assertTrue(stack.camera_active('search'))

    def test_collection_owns_the_camera_above_home_or_library(self):
        for page in ('home', 'videos'):
            with self.subTest(page=page):
                stack = DialogStack(page, 'movies')
                stack.visible.add('11111')
                self.assertFalse(stack.camera_active('movieset'))
                self.assertEqual(stack.open_info(), 'movieset')
                self.assertEqual(stack.follow(), [('11111', '5190')])
                self.assertTrue(stack.camera_active('movieset'))
                self.assertFalse(stack.camera_active('library'))
                stack.visible.remove('12003')
                self.assertFalse(stack.camera_active('movieset'))

    def test_nested_info_does_not_reassign_the_underlying_detail_camera(self):
        stack = DialogStack(section='movies')
        self.assertEqual(stack.open_info(), 'home')
        stack.visible.add('11111')
        self.assertFalse(stack.camera_active('movieset'))
        self.assertEqual(stack.open_info('12016'), 'movieset')
        self.assertEqual(stack.follow(), [('10000', '9090')])
        self.assertEqual(stack.follow('12016'), [('11111', '5190')])
        self.assertTrue(stack.camera_active('movieset'))
        stack.visible.remove('12016')
        self.assertFalse(stack.camera_active('movieset'))
        self.assertEqual(stack.follow(), [('10000', '9090')])

    def test_video_and_disabled_fanart_do_not_zoom_library_background(self):
        stack = DialogStack(page='videos')
        self.assertEqual(stack.open_info(), 'library')
        self.assertEqual(stack.follow(), [('10025', '9490')])
        self.assertTrue(stack.camera_active('library'))
        stack.video = True
        self.assertFalse(stack.camera_active('library'))
        stack.video = False
        stack.no_fanart = True
        self.assertFalse(stack.camera_active('library'))

    def test_standalone_entry_queues_zoom_before_onload_captures_source(self):
        animation = INFO.find('.//control[@id="5900"]/animation[.="WindowOpen"]')
        for page, section, expected in [('home', 'files', True), ('home', 'search', False),
                                        ('home', 'movies', False), ('videos', 'movies', False)]:
            with self.subTest(page=page, section=section):
                stack = DialogStack(page, section)
                self.assertEqual(stack.evaluate(animation.get('condition')), expected)
                self.assertEqual(stack.open_info() == 'fallback', expected)
        stack = DialogStack(section='files')
        stack.visible.add('11111')
        self.assertFalse(stack.evaluate(animation.get('condition')))
        self.assertEqual(stack.open_info(), 'movieset')


if __name__ == '__main__':
    unittest.main()
