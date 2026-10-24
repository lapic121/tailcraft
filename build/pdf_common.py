# -*- coding: utf-8 -*-
"""TailCraft 네트워크 설정 가이드 PDF 생성 (reportlab + Noto Sans CJK KR)"""
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
                                PageBreak, KeepTogether, ListFlowable, ListItem)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

OUT = sys.argv[1]
import os; os.chdir(os.path.dirname(os.path.abspath(__file__))+'/..')
pdfmetrics.registerFont(TTFont('KR', 'build/fonts/NotoSansKR-400.ttf'))
pdfmetrics.registerFont(TTFont('KRB', 'build/fonts/NotoSansKR-700.ttf'))
pdfmetrics.registerFontFamily('KR', normal='KR', bold='KRB', italic='KR', boldItalic='KRB')

ACC = colors.HexColor('#2F6FD6'); MUT = colors.HexColor('#555'); BG = colors.HexColor('#F2F5FA'); WARN = colors.HexColor('#FFF4D6')
S = {
    'title': ParagraphStyle('t', fontName='KRB', fontSize=26, leading=34, textColor=ACC),
    'sub':   ParagraphStyle('s', fontName='KR', fontSize=12, leading=18, textColor=MUT),
    'h1':    ParagraphStyle('h1', fontName='KRB', fontSize=17, leading=24, textColor=ACC, spaceBefore=14, spaceAfter=6),
    'h2':    ParagraphStyle('h2', fontName='KRB', fontSize=13, leading=19, spaceBefore=10, spaceAfter=4),
    'p':     ParagraphStyle('p', fontName='KR', fontSize=10.5, leading=16.5, spaceAfter=5),
    'small': ParagraphStyle('sm', fontName='KR', fontSize=9, leading=13, textColor=MUT),
    'code':  ParagraphStyle('c', fontName='KR', fontSize=9.5, leading=14, backColor=BG, borderPadding=(4, 6, 4, 6), spaceBefore=3, spaceAfter=8),
    'box':   ParagraphStyle('b', fontName='KR', fontSize=10, leading=15, backColor=WARN, borderPadding=(6, 8, 6, 8), spaceBefore=4, spaceAfter=8),
    'th':    ParagraphStyle('th', fontName='KRB', fontSize=9.5, leading=13, textColor=colors.white),
    'td':    ParagraphStyle('td', fontName='KR', fontSize=9.5, leading=13),
}

def P(t, s='p'): return Paragraph(t, S[s])
def H1(t): return P(t, 'h1')
def H2(t): return P(t, 'h2')
def CODE(t): return P(t.replace('\n', '<br/>'), 'code')
def BOX(t): return P(t, 'box')
def UL(items):
    return ListFlowable([ListItem(P(i), leftIndent=12) for i in items], bulletType='bullet', start='•', leftIndent=14, bulletFontName='KR')
def OL(items):
    return ListFlowable([ListItem(P(i), leftIndent=14) for i in items], bulletType='1', leftIndent=16, bulletFontName='KR')
def TBL(head, rows, widths):
    data = [[Paragraph(h, S['th']) for h in head]] + [[Paragraph(c, S['td']) for c in r] for r in rows]
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), ACC), ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, BG]),
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#C9D2E0')),
        ('TOPPADDING', (0, 0), (-1, -1), 5), ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]))
    t.spaceAfter = 8
    return t

def footer(c, d):
    c.saveState(); c.setFont('KR', 8.5); c.setFillColor(MUT)
    c.drawString(20 * mm, 12 * mm, 'TailCraft 네트워크 설정 가이드')
    c.drawRightString(A4[0] - 20 * mm, 12 * mm, f'{d.page}')
    c.restoreState()

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=18 * mm, bottomMargin=20 * mm,
                        title='TailCraft 네트워크 설정 가이드', author='TailCraft')
F = []

