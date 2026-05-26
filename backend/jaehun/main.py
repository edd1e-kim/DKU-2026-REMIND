from fastapi import FastAPI, UploadFile, File, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

import os
import re
import json
import base64
import asyncio
import requests

from bs4 import BeautifulSoup
from typing import List, Tuple, Dict
from pathlib import Path
from uuid import uuid4
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

RAPIDAPI_KEY = os.getenv("RAPIDAPI_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(UPLOAD_DIR)), name="uploads")

client = OpenAI(api_key=OPENAI_API_KEY)

MAX_SUMMARY_INPUT_CHARS = 11000
CHUNK_SIZE = 9000
OCR_PARALLEL_LIMIT = 8

ALLOWED_CATEGORIES = ["장소", "자기계발", "쇼핑", "운동", "기타"]

FAIL_TAG_BLOCKLIST = {
    "분석실패",
    "실패",
    "에러",
    "오류",
    "분석오류",
    "요약실패",
    "확인필요",
}

SNS_BLOCK_KEYWORDS = [
    "좋아요",
    "댓글",
    "공유",
    "저장 필수",
    "저장해두세요",
    "프로필 링크",
    "기다려주세요",
    "댓글에",
    "댓글로",
    "DM",
    "디엠",
    "팔로우",
]

META_PREFIXES = [
    "제목:",
    "주제키:",
    "sourceAccount:",
    "viewerAccount:",
    "captionSnippet:",
    "carouselInfo:",
    "platformHint:",
    "분류힌트:",
    "신뢰도:",
]


def normalize_category(category: str) -> str:
    category = str(category or "").strip()
    return category if category in ALLOWED_CATEGORIES else "기타"


def normalize_tags(tags):
    if not isinstance(tags, list):
        return []

    result = []

    for tag in tags:
        cleaned = str(tag).replace("#", "").strip()

        if not cleaned:
            continue

        if cleaned in FAIL_TAG_BLOCKLIST:
            continue

        if cleaned in ["정보", "추천", "이미지", "콘텐츠", "요약"]:
            continue

        if cleaned not in result:
            result.append(cleaned)

    return result[:3]


def clean_analysis_text(text: str) -> str:
    if not text:
        return ""

    text = text.replace("\r\n", "\n")
    text = text.replace("```", "").replace("`", "")
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()


def clean_display_original_text(text: str) -> str:
    if not text:
        return ""

    text = text.replace("\r\n", "\n")
    text = text.replace("```", "").replace("`", "").strip()

    lines = []

    for raw_line in text.split("\n"):
        line = raw_line.strip()

        if not line:
            lines.append("")
            continue

        if any(line.startswith(prefix) for prefix in META_PREFIXES):
            continue

        if line.startswith("내용:"):
            line = line.replace("내용:", "", 1).strip()
            if not line:
                continue

        lower_line = line.lower()

        if any(
            keyword.lower() in lower_line
            for keyword in ["좋아요", "댓글", "공유", "팔로우", "프로필 링크"]
        ):
            continue

        lines.append(line)

    text = "\n".join(lines)
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()


def clean_summary_text(summary: str) -> str:
    if not summary:
        return ""

    summary = summary.replace("\r\n", "\n")
    summary = summary.replace("```", "").replace("`", "").strip()

    lines = []

    for raw_line in summary.split("\n"):
        line = raw_line.strip()

        if not line:
            continue

        if any(line.startswith(prefix) for prefix in META_PREFIXES):
            continue

        lower_line = line.lower()

        if any(
            keyword.lower() in lower_line
            for keyword in ["팔로우", "댓글 남겨", "공유", "저장해두", "프로필 링크"]
        ):
            continue

        # AI가 앞에 붙이는 점 제거
        line = re.sub(r"^[•●▪▫]\s*", "", line).strip()

        # "• - 내용" 같은 형태면 "- 내용"만 남김
        line = re.sub(r"^[•●▪▫]\s*(-\s*)", r"\1", line).strip()
        # 체크리스트 원형 제거
        line = re.sub(r"^(\d+[\)\.]\s*)[○◯☐□]\s*", r"\1", line).strip()
        line = re.sub(r"^[-–]\s*[○◯☐□]\s*", "- ", line).strip()
        line = re.sub(r"^[○◯☐□]\s*", "", line).strip()
        
        line = re.sub(r"\s+", " ", line).strip()

        if line:
            lines.append(line)

    return "\n".join(lines)


def split_text_by_length(text: str, max_chars: int = CHUNK_SIZE) -> List[str]:
    if len(text) <= max_chars:
        return [text]

    paragraphs = text.split("\n")
    chunks = []
    current = ""

    for paragraph in paragraphs:
        paragraph = paragraph.strip()

        if not paragraph:
            continue

        if len(paragraph) > max_chars:
            if current.strip():
                chunks.append(current.strip())
                current = ""

            for i in range(0, len(paragraph), max_chars):
                chunks.append(paragraph[i:i + max_chars].strip())

            continue

        if len(current) + len(paragraph) + 1 > max_chars:
            if current.strip():
                chunks.append(current.strip())
            current = paragraph
        else:
            current = f"{current}\n{paragraph}".strip()

    if current.strip():
        chunks.append(current.strip())

    return chunks


def make_short_summary_from_detail(summary: str) -> str:
    if not summary:
        return ""

    lines = [line.strip() for line in summary.split("\n") if line.strip()]
    useful_lines = []

    for line in lines:
        if line.startswith("<") and line.endswith(">"):
            continue
        useful_lines.append(line)

    return "\n".join(useful_lines[:6])

def is_text_heavy_numbered_content(text: str) -> bool:
    if not text:
        return False

    lines = [line.strip() for line in text.split("\n") if line.strip()]
    numbered_count = 0

    for line in lines:
        if re.match(r"^\d+[\)\.]\s*", line):
            numbered_count += 1

    return numbered_count >= 5


def clean_original_for_summary(text: str) -> str:
    if not text:
        return ""

    text = text.replace("\r\n", "\n")
    text = text.replace("```", "").replace("`", "").strip()

    lines = []

    for raw_line in text.split("\n"):
        line = raw_line.strip()

        if not line:
            lines.append("")
            continue

        if re.match(r"^\[이미지\s*\d+\]$", line):
            continue

        if any(line.startswith(prefix) for prefix in META_PREFIXES):
            continue

        lower_line = line.lower()

        if any(
            keyword.lower() in lower_line
            for keyword in [
                "좋아요",
                "댓글",
                "공유",
                "팔로우",
                "프로필 링크",
                "저장해두세요",
                "돈 버는 비밀을 알려줄게",
                "리치언니",
            ]
        ):
            continue

        lines.append(line)

    cleaned = "\n".join(lines)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)

    return cleaned.strip()


def get_first_number_from_line(line: str):
    if not line:
        return None

    match = re.match(r"^\s*(\d+)[\)\.]\s*", line.strip())

    if not match:
        return None

    try:
        return int(match.group(1))
    except Exception:
        return None


def normalize_number_prefix(line: str) -> str:
    line = str(line or "").strip()
    line = re.sub(r"^(\d+)[\)\.]\s*", r"\1. ", line)
    return line.strip()


def simplify_numbered_line(line: str) -> str:
    simple = str(line or "").strip()

    for divider in ["->", "→", "▶", "➔", ":"]:
        if divider in simple:
            left = simple.split(divider, 1)[0].strip()

            if get_first_number_from_line(left) is not None:
                simple = left
                break

    simple = re.sub(r"\s+", " ", simple).strip()
    simple = normalize_number_prefix(simple)

    return simple


def make_short_summary_from_original_text(text: str) -> str:
    if not text:
        return ""

    cleaned = clean_original_for_summary(text)
    lines = [line.strip() for line in cleaned.split("\n") if line.strip()]

    title = ""
    numbered_items = []
    seen_numbers = set()

    for line in lines:
        if line.startswith("[이미지"):
            continue

        if re.match(r"^\d+[\)\.]\s*", line):
            continue

        cleaned_line = line.replace("<", "").replace(">", "").strip()

        if cleaned_line and len(cleaned_line) <= 45:
            title = cleaned_line
            break

    for line in lines:
        number = get_first_number_from_line(line)

        if number is None:
            continue

        simple = simplify_numbered_line(line)

        if not simple:
            continue

        if number in seen_numbers:
            continue

        seen_numbers.add(number)
        numbered_items.append((number, simple))

    if numbered_items:
        numbered_items.sort(key=lambda item: item[0])
        sorted_lines = [item[1] for item in numbered_items]

        if title:
            return f"<{title}>\n\n" + "\n".join(sorted_lines)

        return "\n".join(sorted_lines)

    fallback = []

    for line in lines:
        if line.startswith("[이미지"):
            continue

        simple = simplify_numbered_line(line)

        if simple:
            fallback.append(simple)

        if len(fallback) >= 6:
            break

    if title and fallback:
        return f"<{title}>\n\n" + "\n".join(fallback)

    return "\n".join(fallback)

def build_preserved_summary_from_original_text(text: str) -> str:
    if not text:
        return ""

    cleaned = clean_original_for_summary(text)
    lines = [line.strip() for line in cleaned.split("\n") if line.strip()]

    result = []
    section_count = 0
    title_skipped = False

    for line in lines:
        if line.startswith("[이미지"):
            continue

        # 제목처럼 보이는 첫 줄은 summary에 넣지 않음
        # 제목은 Firestore title 필드에서 이미 보여주기 때문
        if not title_skipped and len(line) <= 60 and not re.match(r"^\d+[\)\.]\s*", line):
            title_skipped = True
            continue

        lower_line = line.lower()

        if any(
            keyword.lower() in lower_line
            for keyword in [
                "좋아요",
                "댓글",
                "공유",
                "팔로우",
                "프로필 링크",
                "저장해두세요",
            ]
        ):
            continue

        # 1) 항목 / 1. 항목 → 세부 항목으로 바꿈
        # 화면에서 번호 줄이 볼드 처리되는 문제 방지
        if re.match(r"^\d+[\)\.]\s*", line):
            item_text = re.sub(r"^\d+[\)\.]\s*", "", line).strip()
            if item_text:
                result.append(f"- {item_text}")
            continue

        # 짧은 문장은 섹션 제목으로 처리
        if len(line) <= 35:
            if result and result[-1] != "":
                result.append("")

            section_count += 1
            result.append(f"{section_count}) {line}")
            continue

        # 긴 설명문은 일반 문장으로 유지
        result.append(line)

    summary = "\n".join(result)
    summary = re.sub(r"\n{3,}", "\n\n", summary)

    return summary.strip()


def make_short_summary_from_preserved_text(text: str) -> str:
    if not text:
        return ""

    preserved = build_preserved_summary_from_original_text(text)
    lines = [line.strip() for line in preserved.split("\n") if line.strip()]

    title = ""
    headings = []

    for line in lines:
        if line.startswith("<") and line.endswith(">"):
            title = line
            continue

        # 1. 수납박스도 비워라 / 5. 옷 쇼핑 기준
        if re.match(r"^\d+[\)\.]\s*", line):
            simple = simplify_numbered_line(line)
            if simple and simple not in headings:
                headings.append(simple)
            continue

        # 과감히 비워라 / 옷은 많을 필요가 없다 / 옷장은 80%만 채우자
        if (
            len(line) <= 32
            and not line.startswith("✓")
            and not line.startswith("①")
            and not line.startswith("②")
            and not line.startswith("③")
            and "。" not in line
            and "." not in line[-1:]
            and "합니다" not in line
            and "됩니다" not in line
        ):
            if line not in headings:
                headings.append(line)

    # 너무 많이 나오면 10개까지만
    headings = headings[:10]

    if title and headings:
        return f"{title}\n\n" + "\n".join(headings)

    return "\n".join(headings[:10])

def build_summary_prompt(content: str, mode: str = "full") -> str:
    if mode == "chunk":
        mode_instruction = """
[현재 작업]
이 본문은 긴 콘텐츠의 일부야.
정보성 텍스트를 절대 요약해서 날리지 말고, 보이는 항목과 문장을 최대한 보존해서 정리해.
나중에 여러 부분 정리를 다시 합칠 예정이므로, 세부 정보와 흐름을 보존해.
"""
    elif mode == "final":
        mode_instruction = """
[현재 작업]
아래 본문은 긴 콘텐츠를 여러 부분으로 나누어 정리한 중간 정리본들이야.
중복만 줄이고, 정보성 내용은 삭제하지 말고 하나의 완성된 원본 대체용 정리본으로 통합해.
사용자가 원본을 다시 보지 않아도 전체 내용을 이해할 수 있게 작성해.
"""
    else:
        mode_instruction = """
[현재 작업]
아래 본문 전체를 분석해서 원본 대체용 정리본을 작성해.
"""

    return f"""
너는 저장형 콘텐츠 앱 ReSee의 요약 전문가야.
아래 본문을 한국어로 분석해서 반드시 JSON만 반환해.

{mode_instruction}

[출력 JSON 형식]
{{
  "title": "제목",
  "summary": "자세히 보기용 전체 정리",
  "shortSummary": "핵심만 보기용 압축 정리",
  "category": "카테고리",
  "tags": ["태그1", "태그2", "태그3"]
}}

[핵심 원칙]
1. summary는 자세히 보기용이다. 핵심만 간단히 줄이지 말고, 정보성 텍스트를 최대한 모두 포함해.
2. shortSummary만 핵심만 보기용이다. summary를 짧게 만들지 마.
3. summary는 문단형으로 길게 쓰지 말고, 사용자가 바로 읽기 좋게 리스트형으로 정리해.
4. 불필요한 것은 SNS 행동 유도, 계정 홍보, 좋아요/댓글/공유/저장 유도, 앱 UI 문구뿐이다.
5. 실제 본문 내용, 번호 목록, 기준, 방법, 예시, 주의사항은 삭제하지 마.
6. sourceAccount, viewerAccount, captionSnippet, carouselInfo, platformHint, 신뢰도 같은 분석용 메타데이터는 title, summary, shortSummary에 절대 쓰지 마.
7. 화면 상단의 블로그/앱 섹션명, 예를 들어 "journal", "사랑과 투쟁!", "통계" 같은 것은 제목 후보가 아니라 출처/섹션명으로 보고, 핵심 주제가 아니면 title에 쓰지 마.
8. 여러 장의 이미지가 하나의 게시물로 묶이면 모든 이미지의 핵심 내용을 반드시 포함해. 특히 첫 이미지의 도입, 고민, 배경 설명을 생략하지 마.
9. 단순히 번호 목록만 요약하지 말고, 글쓴이가 왜 이 행동을 하게 되었는지에 대한 맥락도 포함해.

[title 규칙]
1. 본문 내용을 대표하는 자연스러운 제목을 작성해.
2. 원문에 핵심 제목이 보이면 최대한 그 제목을 살려서 작성해.
3. 팔로우, 댓글, 저장, 공유 같은 SNS 유도 문구를 제목에 넣지 마.
4. OCR 원문에 없는 서비스명, 브랜드명, 할인 정보, 장소명은 제목에 절대 넣지 마.
5. 너무 길면 의미를 유지해서 45자 이내로 줄여.

[summary 리스트형 출력 규칙]
1. 원문 구조를 최우선으로 유지해.
2. 여러 이미지로 구성된 콘텐츠에서 첫 이미지가 문제 제기, 배경 설명, 감정, 고민, 도입부 역할을 하면 절대 생략하지 마.
3. 첫 이미지가 제목 없는 도입부라면 "1) 시작 배경", "1) 익숙함에서 벗어나고 싶어진 이유"처럼 자연스러운 섹션명으로 정리해.
4. 번호가 1, 2, 3처럼 이어지는 콘텐츠는 첫 번째 번호 제목을 절대 삭제하지 마.
5. "1. 굳이 멀리 있는 카페 찾아가기"처럼 번호 제목이 있으면 섹션 제목으로 반드시 살려. 단, 앞에 도입부 섹션을 추가했다면 전체 순서에 맞게 번호만 다시 매겨.
6. 각 이미지의 핵심 내용은 최소 한 줄 이상 summary에 포함해.
7. 큰 묶음 이름은 원문에 실제로 있는 제목이나 주제에 맞게 작성해.
8. 원문에 모닝 루틴, 데이 루틴, 나이트 루틴이 실제로 없으면 절대 그 표현을 만들지 마.
9. 제품 추천 콘텐츠는 제품명을 큰 묶음 제목으로 사용해. "1) 제품명", "2) 제품명"처럼 제품별로 나누고, 가격/색상/특징은 아래 "- 설명"으로 정리해.
10. 제품 추천 콘텐츠를 "추천 제품", "제품 목록", "제품별 특징" 같은 하나의 큰 묶음으로 합치지 마.
11. 큰 묶음 아래 세부 항목은 반드시 "- 항목명" 형태로 줄바꿈해서 작성해.
12. 한 문단으로 길게 합치지 마.
13. 원문에 있는 체크리스트 항목은 삭제하지 말고 줄바꿈 리스트로 유지해.
14. 원문에 보이는 괄호 설명, 시간, 용량, 조건은 유지해.
15. 원문에 없는 내용은 추가하지 마.
16. 중간에 ...으로 줄이지 마.
17. 아래 예시는 형식 참고용이다. 원문 내용과 구조가 다르면 예시를 따라 하지 말고 원문 구조를 우선해.

[예시 형식]
원문이 식단 추천 콘텐츠라면:

1) 아침 식단 추천
- 고구마 + 삶은 계란 + 견과류: 지방을 줄이고 싶다면 노른자는 조절하고, 삶은 계란은 충분히 섭취
- 위트빅스 + 아몬드유 + 이데아 시리얼: 위트빅스는 성인 여성 기준 3~5개 권장
- 오트밀 + 우유 또는 두유 + 프로틴 파우더: 설탕 없는 순수 오트밀 사용
- 현미밥 + 아보카도 + 닭가슴살: 다이어트할 때 좋은 식단 조합

2) 식단 구성 기준
- 건강한 재료로 구성하기
- 단백질과 포만감을 챙기기
- 다이어트 목적에 맞게 양 조절하기

원문이 루틴 콘텐츠라면:

1) 모닝 루틴
- 원문에 있는 모닝 루틴 항목

2) 데이 루틴
- 원문에 있는 데이 루틴 항목

3) 나이트 루틴
- 원문에 있는 나이트 루틴 항목

[shortSummary 규칙]
1. shortSummary는 핵심만 보기용이다.
2. shortSummary는 summary 앞 3줄 복사가 아니라 전체 내용을 압축한 핵심 정리다.
3. shortSummary에는 "▶ 설명", "➔ 설명", ": 설명" 같은 세부 설명을 최대한 빼고 행동명 중심으로만 작성해.
4. shortSummary는 3~6개 항목 정도로 작성한다.
5. shortSummary도 "•" 점 bullet을 쓰지 마.
6. 큰 묶음이 있으면 원문에 실제로 있는 섹션명이나 콘텐츠 주제에 맞는 섹션명을 사용해.
7. 원문에 모닝 루틴, 데이 루틴, 나이트 루틴이 실제로 없으면 shortSummary에도 절대 그 표현을 만들지 마.
8. 아래 예시는 형식 참고용이다. 원문에 없는 섹션명은 만들지 마.

원문이 식단 추천 콘텐츠라면:

1) 식단 핵심
- 추천 식단 조합 정리
- 단백질과 포만감 중심으로 구성
- 다이어트 목적에 맞게 양 조절

원문이 체크리스트 콘텐츠라면:

1) 핵심 체크리스트
- 실천 항목 정리
- 주의할 점 정리
- 반복해서 확인할 기준 정리

원문이 루틴 콘텐츠라면:

1) 원문에 있는 루틴명
- 핵심 행동
- 핵심 행동

[category 규칙]
1. category는 반드시 장소, 자기계발, 쇼핑, 운동, 기타 중 하나만 써.
2. 백엔드는 현재 사용자가 추가한 카테고리 목록을 알 수 없다.
3. 다이어트, 요리, 투자, 음악처럼 사용자가 직접 추가했을 수 있는 세부 주제는 category로 쓰지 말고 tags에 넣어.
4. 공부법, 시간관리, 독서, 기록, 목표관리, 생산성, 습관, 삶의 태도, 자기관리는 자기계발로 분류해.
5. 상품 추천, 구매 정보, 할인, 가격 비교, 쇼핑몰, 아이템 추천은 쇼핑으로 분류해.
6. 운동 루틴, 홈트, 헬스, 스트레칭 자체가 핵심이면 운동으로 분류해.
7. 맛집, 카페, 여행지, 전시, 데이트 장소, 방문 장소는 장소로 분류해.
8. 다이어트 루틴, 식단 관리, 요리, 투자, 음악처럼 세부 카테고리 후보인 경우 category는 기타로 두고 tags에 해당 키워드를 넣어.
9. 위 기준에 명확히 맞지 않으면 기타로 분류해.

[tags 규칙]
1. tags는 # 없이 2개에서 3개만 써.
2. 실패, 에러, 분석실패, 오류 같은 단어를 tags에 넣지 마.
3. tags는 나중에 새 카테고리 추천 후보로 사용할 수 있는 세부 주제를 넣어.
4. 다이어트, 요리, 투자, 음악처럼 세부 주제가 명확하면 tags에 해당 키워드를 반드시 포함해.
5. 루틴형 콘텐츠는 tags에 하루루틴, 자기관리, 습관 중 실제 내용에 맞는 키워드를 넣어.
6. 너무 넓은 태그인 정보, 추천, 이미지 같은 단어는 피하고 실제 사용자가 다시 찾을 키워드를 넣어.

본문:
{content}
"""


def call_summary_ai(content: str, mode: str = "full"):
    prompt = build_summary_prompt(content, mode=mode)

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {
                "role": "system",
                "content": "너는 JSON만 반환하는 저장형 콘텐츠 요약기야. summary는 자세히 보기용 전체 정리, shortSummary는 핵심만 보기용으로 작성해.",
            },
            {
                "role": "user",
                "content": prompt,
            },
        ],
        temperature=0,
        response_format={"type": "json_object"},
    )

    res = json.loads(response.choices[0].message.content.strip())

    title = str(res.get("title", "분석된 제목")).strip()
    summary = clean_summary_text(str(res.get("summary", "")).strip())
    short_summary = clean_summary_text(str(res.get("shortSummary", "")).strip())
    category = normalize_category(str(res.get("category", "기타")).strip())
    tags = normalize_tags(res.get("tags", []))

    if not short_summary:
        short_summary = make_short_summary_from_detail(summary)

    return title, summary, short_summary, category, tags


def get_ai_summary(content: str):
    if not content or content == "내용 없음" or len(content.strip()) < 10:
        return "제목 없음", "정보를 추출할 본문이 부족합니다.", "정보를 추출할 본문이 부족합니다.", "기타", ["내용부족"]

    try:
        content = content.strip()

        if len(content) <= MAX_SUMMARY_INPUT_CHARS:
            return call_summary_ai(content, mode="full")

        chunks = split_text_by_length(content, CHUNK_SIZE)
        partial_summaries = []

        for index, chunk in enumerate(chunks, 1):
            part_title, part_summary, part_short_summary, part_category, part_tags = call_summary_ai(
                chunk,
                mode="chunk",
            )

            partial_summaries.append(
                f"[부분 {index}]\n"
                f"제목: {part_title}\n"
                f"카테고리: {part_category}\n"
                f"태그: {', '.join(part_tags)}\n"
                f"핵심 요약:\n{part_short_summary}\n"
                f"자세한 정리:\n{part_summary}"
            )

        combined = "\n\n".join(partial_summaries)

        while len(combined) > MAX_SUMMARY_INPUT_CHARS:
            reduced_chunks = split_text_by_length(combined, CHUNK_SIZE)
            reduced_summaries = []

            for index, chunk in enumerate(reduced_chunks, 1):
                part_title, part_summary, part_short_summary, part_category, part_tags = call_summary_ai(
                    chunk,
                    mode="chunk",
                )

                reduced_summaries.append(
                    f"[통합 전 부분 {index}]\n"
                    f"제목: {part_title}\n"
                    f"카테고리: {part_category}\n"
                    f"태그: {', '.join(part_tags)}\n"
                    f"핵심 요약:\n{part_short_summary}\n"
                    f"자세한 정리:\n{part_summary}"
                )

            combined = "\n\n".join(reduced_summaries)

        return call_summary_ai(combined, mode="final")

    except Exception as e:
        print("AI summary error:", e)
        return "분석 실패", "내용 요약 중 에러 발생", "내용 요약 중 에러 발생", "기타", ["이미지"]


def get_ai_grouped_summaries(image_texts: List[str], original_texts: List[str]):
    if not image_texts:
        return []

    joined_text = "\n\n".join(image_texts)

    try:
        prompt = f"""
너는 저장형 콘텐츠 앱 ReSee의 스크린샷 분류 전문가야.
사용자가 여러 장의 스크린샷을 한 번에 업로드했어.
아래 이미지별 OCR 텍스트를 보고, 같은 게시물끼리 먼저 묶고 그 안에서 주제가 이어지는지 판단해서 카드 여러 개로 만들어줘.

반드시 JSON만 반환해.

[출력 JSON 형식]
{{
  "groups": [
    {{
      "title": "카드 제목",
      "summary": "자세히 보기용 전체 정리",
      "shortSummary": "핵심만 보기용 압축 정리",
      "category": "카테고리",
      "tags": ["태그1", "태그2", "태그3"],
      "imageIndexes": [0, 1]
    }}
  ]
}}

[그룹 기준]
1. 인스타그램/릴스/스토리 캡처는 본문 주제보다 sourceAccount, captionSnippet, carouselInfo를 우선해서 같은 게시물인지 판단해.
2. sourceAccount는 화면 상단 이름이 아니라 하단 프로필 아이디를 우선 기준으로 판단해.
3. viewerAccount는 카드 분류 기준으로 쓰지 마.
4. sourceAccount가 같고 captionSnippet이 같거나 매우 비슷하면 같은 게시물로 보고 같은 group으로 묶어.
5. sourceAccount가 같고 carouselInfo가 1/5, 2/5, 3/5처럼 이어지면 같은 게시물로 보고 같은 group으로 묶어.
6. sourceAccount가 다르면 제목이나 주제가 비슷해도 반드시 다른 group으로 나눠.
7. captionSnippet이 명확히 다르면 같은 계정이어도 다른 group으로 나눠.
8. sourceAccount와 captionSnippet이 둘 다 다르면 절대 같은 group으로 묶지 마.
9. sourceAccount가 없거나 captionSnippet이 없을 때만 제목, 주제키, 분류힌트를 기준으로 묶어.
10. 같은 게시물로 확인되지 않으면 무리해서 묶지 말고 분리해.
11. 모든 이미지는 최소 한 그룹에는 포함되어야 해.
12. 같은 이미지를 여러 그룹에 중복 배정하지 마.
13. imageIndexes는 반드시 0부터 시작하는 내부 번호를 사용해.

[summary 형식]
1. summary는 자세히 보기용 원본 대체 정리본이다.
2. 핵심만 짧게 줄이지 말고, OCR 원문에 있는 정보성 내용을 최대한 유지해.
3. 원문에 있는 구조를 우선해서 정리해.
4. 원문에 모닝 루틴, 데이 루틴, 나이트 루틴이 실제로 있을 때만 그 표현을 사용해.
5. 원문에 모닝 루틴, 데이 루틴, 나이트 루틴이 없으면 절대 그 표현을 만들지 마.
6. 원문이 식단 추천 콘텐츠라면 식단 조합이나 식단 종류를 큰 묶음으로 정리해.
7. 원문이 제품 추천 콘텐츠라면 제품명을 큰 묶음 제목으로 사용해. "1) 제품명", "2) 제품명", "3) 제품명"처럼 제품별로 나누고, 가격/색상/특징은 아래 "- 설명"으로 정리해.
8. 제품 추천 콘텐츠를 "추천 제품", "제품 목록", "제품별 특징" 같은 하나의 큰 묶음으로 합치지 마.
9. 원문이 체크리스트 콘텐츠라면 원문에 있는 체크 항목을 줄바꿈 리스트로 유지해.
10. 큰 묶음 아래 세부 항목은 반드시 "- 항목명" 형태로 줄바꿈해서 작성해.
11. 한 문단으로 합치지 마.
12. 원문에 있는 체크리스트 항목은 삭제하지 말고 줄바꿈 리스트로 유지해.
13. 원문에 보이는 괄호 설명, 시간, 용량, 조건은 유지해.
14. 원문에 없는 내용은 추가하지 마.
15. sourceAccount, viewerAccount, captionSnippet, carouselInfo, platformHint, 신뢰도 같은 분석용 메타데이터는 summary에 쓰지 마.
16. 여러 이미지가 하나의 group으로 묶였으면, group 안의 모든 이미지 내용을 summary에 반드시 포함해.
17. [이미지 1], [이미지 2], [이미지 3], [이미지 5]처럼 이미지 번호가 나뉘어 있으면 각 이미지의 핵심 주제를 빠뜨리지 마.
18. 이미지 하나가 하나의 섹션이면 summary도 섹션 단위로 정리해.
19. 특정 이미지 내용이 다른 이미지보다 덜 중요해 보여도 생략하지 마.
20. 제품 추천형 콘텐츠는 제품별로 모두 정리해. 제품명이 보이면 제품명을 섹션 제목으로 사용해.
21. summary는 길어져도 괜찮다. 빠뜨리는 것보다 길게 쓰는 것을 우선해.
22. 첫 이미지가 도입부, 고민, 배경 설명이면 절대 생략하지 마.
23. 번호가 이어지는 콘텐츠에서 1번 제목을 삭제하지 마.
24. "1. 굳이 멀리 있는 카페 찾아가기" 같은 제목은 반드시 섹션 제목으로 살려.
25. 각 이미지의 핵심 내용은 최소 한 줄 이상 summary에 포함해.
26. 첫 이미지가 제목 없는 도입부라면 "1) 시작 배경", "1) 익숙함에서 벗어나고 싶어진 이유"처럼 자연스러운 섹션명으로 정리해.

[summary 예시]
식단 추천 콘텐츠라면:

1) 아침 식단 추천
- 고구마 + 삶은 계란 + 견과류: 지방 조절과 포만감에 도움
- 위트빅스 + 아몬드유 + 시리얼: 간단하게 먹기 좋은 조합
- 오트밀 + 우유 또는 두유 + 프로틴 파우더: 단백질 보충 가능
- 현미밥 + 아보카도 + 닭가슴살: 든든한 식단 조합

2) 식단 구성 기준
- 단백질과 포만감을 챙기기
- 설탕이 많은 재료는 줄이기
- 목적에 맞게 양 조절하기

루틴 콘텐츠라면:

1) 원문에 있는 루틴명
- 원문에 있는 세부 행동
- 원문에 있는 세부 행동

[shortSummary 규칙]
1. shortSummary는 핵심만 보기용이다.
2. summary 앞 3줄 복사 금지.
3. 전체 내용을 압축하되, 이미지별 큰 주제는 모두 포함해.
4. 여러 이미지가 있으면 각 이미지의 대표 주제를 1줄씩 포함해.
5. 원문에 없는 섹션명이나 예시를 만들지 마.
6. 원문이 식단 추천이면 식단 추천 핵심만 정리해.
7. 원문이 제품 추천이면 제품명과 핵심 특징을 정리해. 제품군으로 뭉뚱그리지 마.
8. 원문이 루틴이면 원문에 있는 루틴명만 사용해.
9. shortSummary도 줄바꿈 리스트로 작성해.

[category 규칙]
1. category는 반드시 장소, 자기계발, 쇼핑, 운동, 기타 중 하나만 써.
2. 백엔드는 현재 사용자가 추가한 카테고리 목록을 알 수 없다.
3. 다이어트, 요리, 투자, 음악처럼 사용자가 직접 추가했을 수 있는 세부 주제는 category로 쓰지 말고 tags에 넣어.
4. 공부법, 시간관리, 독서, 기록, 목표관리, 생산성, 습관, 삶의 태도, 자기관리는 자기계발로 분류해.
5. 상품 추천, 구매 정보, 할인, 가격 비교, 쇼핑몰, 아이템 추천은 쇼핑으로 분류해.
6. 운동 루틴, 홈트, 헬스, 스트레칭 자체가 핵심이면 운동으로 분류해.
7. 맛집, 카페, 여행지, 전시, 데이트 장소, 방문 장소는 장소로 분류해.
8. 다이어트 루틴, 식단 관리, 요리, 투자, 음악처럼 세부 카테고리 후보인 경우 category는 기타로 두고 tags에 해당 키워드를 넣어.
9. 위 기준에 명확히 맞지 않으면 기타로 분류해.

[tags 규칙]
1. tags는 # 없이 2개에서 3개만 써.
2. 실패, 에러, 분석실패, 오류 같은 단어를 tags에 넣지 마.
3. tags는 나중에 새 카테고리 추천 후보로 사용할 수 있는 세부 주제를 넣어.
4. 다이어트, 요리, 투자, 음악처럼 세부 주제가 명확하면 tags에 해당 키워드를 반드시 포함해.
5. 루틴형 콘텐츠는 tags에 하루루틴, 자기관리, 습관 중 실제 내용에 맞는 키워드를 넣어.
6. 너무 넓은 태그인 정보, 추천, 이미지 같은 단어는 피하고 실제 사용자가 다시 찾을 키워드를 넣어.

[예시]
[이미지 1] sourceAccount가 "lilly_yori"이고 captionSnippet이 "예전에는 다이어트라고 하면 무조건 참고"이며 carouselInfo가 "1/6",
[이미지 2] sourceAccount가 "lilly_yori"이고 같은 captionSnippet이며 carouselInfo가 "3/6"이면:
하나의 group으로 묶어.

[이미지 1] sourceAccount가 "stay_withyul"이고 [이미지 2] sourceAccount가 "badajour"이면:
둘 다 자기계발이어도 반드시 다른 group으로 나눠.

[이미지별 OCR 텍스트]
{joined_text}
"""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "너는 JSON만 반환하는 스크린샷 주제 분류기야. summary는 자세히 보기용 전체 정리, shortSummary는 핵심만 보기용으로 작성해.",
                },
                {
                    "role": "user",
                    "content": prompt,
                },
            ],
            temperature=0,
            response_format={"type": "json_object"},
        )

        res = json.loads(response.choices[0].message.content.strip())
        raw_groups = res.get("groups", [])

        if not isinstance(raw_groups, list):
            return []

        groups = []
        used_indexes = set()

        for group in raw_groups:
            if not isinstance(group, dict):
                continue

            raw_indexes = group.get("imageIndexes", [])
            if not isinstance(raw_indexes, list):
                raw_indexes = []

            image_indexes = []

            for item in raw_indexes:
                try:
                    index = int(item)
                    if 0 <= index < len(image_texts) and index not in image_indexes:
                        image_indexes.append(index)
                except Exception:
                    pass

            if not image_indexes:
                continue

            for index in image_indexes:
                used_indexes.add(index)

            title = str(group.get("title", "스크린샷 분석 결과")).strip()
            summary = clean_summary_text(str(group.get("summary", "")).strip())
            short_summary = clean_summary_text(str(group.get("shortSummary", "")).strip())
            category = normalize_category(str(group.get("category", "기타")).strip())
            tags = normalize_tags(group.get("tags", []))

            original_text = "\n\n".join([
                original_texts[i]
                for i in image_indexes
                if 0 <= i < len(original_texts)
            ]).strip()

            original_text = clean_display_original_text(original_text)

            is_long_multi_image_text = (
                len(image_indexes) >= 3
                and len(original_text) >= 800
            )

            if is_long_multi_image_text:
                summary = build_preserved_summary_from_original_text(original_text)
                short_summary = make_short_summary_from_preserved_text(original_text)
            elif is_text_heavy_numbered_content(original_text):
                summary = clean_original_for_summary(original_text)
                short_summary = make_short_summary_from_original_text(original_text)
            else:
                if not short_summary:
                    short_summary = make_short_summary_from_detail(summary)
            
            if not tags:
                tags = ["이미지"]

            groups.append(
                {
                    "url": "uploaded_image",
                    "title": title or "스크린샷 분석 결과",
                    "summary": summary or "이미지 내용을 분석했습니다.",
                    "shortSummary": short_summary or summary or "이미지 내용을 분석했습니다.",
                    "detailSummary": summary or "이미지 내용을 분석했습니다.",
                    "category": category,
                    "tags": tags,
                    "thumbnail": "",
                    "status": "COMPLETED",
                    "originalText": original_text,
                    "imageIndexes": image_indexes,
                }
            )

        missing_indexes = [
            index for index in range(len(image_texts))
            if index not in used_indexes
        ]

        # AI가 일부 이미지를 group에서 빠뜨렸을 때 보정
        # 이미 의미 있는 group이 1개뿐이면 빠진 이미지를 그 group에 합침
        if missing_indexes and len(groups) == 1:
            main_group = groups[0]

            current_indexes = main_group.get("imageIndexes", [])
            merged_indexes = sorted(list(set(current_indexes + missing_indexes)))

            merged_original_text = "\n\n".join([
                original_texts[i]
                for i in merged_indexes
                if 0 <= i < len(original_texts)
            ]).strip()

            merged_original_text = clean_display_original_text(merged_original_text)

            main_group["imageIndexes"] = merged_indexes
            main_group["originalText"] = merged_original_text

            if len(merged_original_text) >= 800:
                main_group["summary"] = build_preserved_summary_from_original_text(
                    merged_original_text
                )
                main_group["shortSummary"] = make_short_summary_from_preserved_text(
                    merged_original_text
                )
                main_group["detailSummary"] = main_group["summary"]

        # group이 여러 개라 어디에 붙일지 애매한 경우만 따로 카드 생성
        elif missing_indexes:
            for index in missing_indexes:
                original_text = clean_display_original_text(original_texts[index])
                title = "스크린샷 분석 결과"

                if original_text:
                    first_line = original_text.split("\n")[0].strip()
                    if first_line:
                        title = first_line[:45]

                groups.append(
                    {
                        "url": "uploaded_image",
                        "title": title,
                        "summary": original_text or "이미지 내용을 분석했습니다.",
                        "shortSummary": original_text or "이미지 내용을 분석했습니다.",
                        "detailSummary": original_text or "이미지 내용을 분석했습니다.",
                        "category": "기타",
                        "tags": ["이미지"],
                        "thumbnail": "",
                        "status": "COMPLETED",
                        "originalText": original_text,
                        "imageIndexes": [index],
                    }
                )

        return groups

    except Exception as e:
        print("AI grouped summary error:", e)
        return []


def get_instagram_data(url: str):
    headers = {
        "x-rapidapi-key": RAPIDAPI_KEY or "",
        "x-rapidapi-host": "instagram-scraper-stable-api.p.rapidapi.com",
    }

    match = re.search(r"/(?:p|reel|reels)/([A-Za-z0-9_-]+)", url)
    media_code = match.group(1) if match else ""

    try:
        res = requests.get(
            "https://instagram-scraper-stable-api.p.rapidapi.com/get_media_data_v2.php",
            headers=headers,
            params={"media_code": media_code},
            timeout=10,
        ).json()

        item = (res.get("data") or res.get("items") or [res])[0]

        content = (
            item.get("edge_media_to_caption", {})
            .get("edges", [{}])[0]
            .get("node", {})
            .get("text")
            or item.get("caption", {}).get("text")
            or "내용 없음"
        )

        thumbnail = item.get("display_url") or item.get("thumbnail_url") or ""

        return "Instagram 콘텐츠", content, thumbnail

    except Exception as e:
        print("Instagram data error:", e)
        return "Instagram 콘텐츠", "내용 없음", ""


def get_web_data(url: str):
    try:
        if "blog.naver.com" in url and "PostView.naver" not in url:
            match = re.search(r"blog\.naver\.com/([A-Za-z0-9_-]+)/(\d+)", url)

            if match:
                blog_id = match.group(1)
                log_no = match.group(2)
                url = f"https://blog.naver.com/PostView.naver?blogId={blog_id}&logNo={log_no}"

        res = requests.get(
            url,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            },
            timeout=10,
        )

        soup = BeautifulSoup(res.text, "html.parser")

        og_title = soup.find("meta", property="og:title")

        title = (
            og_title.get("content").strip()
            if og_title
            else (soup.title.string.strip() if soup.title else "제목 없음")
        )

        body = ""

        if soup.body:
            naver_content = soup.find(class_="se-main-container") or soup.find(id="postViewArea")

            if naver_content:
                body = naver_content.get_text(separator="\n", strip=True)
            else:
                body = soup.body.get_text(separator="\n", strip=True)

        og = soup.find("meta", property="og:image")
        thumbnail = og.get("content") if og else ""

        return title, body or "내용 없음", thumbnail

    except Exception as e:
        print("Web data error:", e)
        return "제목 없음", "내용 없음", ""


def extract_image_text(base64_image: str) -> Dict[str, str]:
    try:
        res = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": """
이미지 안에 실제로 보이는 텍스트만 한국어로 추출해줘.
반드시 JSON만 반환해.

[출력 JSON 형식]
{
  "visibleTitle": "이미지에서 가장 크게 보이는 실제 콘텐츠 제목",
  "content": "이미지에서 실제로 읽을 수 있는 본문 텍스트. 번호 목록은 가능한 한 전부 보존",
  "originalOnlyText": "사용자에게 원본 글로 보여줄 텍스트. 제목과 본문만 원문 그대로 줄바꿈 유지",
  "topicKey": "이 이미지의 실제 주제를 짧게 표현",
  "categoryHint": "장소|자기계발|쇼핑|운동|기타",
  "sourceAccount": "게시물을 올린 실제 계정명. 인스타그램 화면에서는 보통 하단 프로필 아이디. 없으면 빈 문자열",
  "viewerAccount": "화면 상단에 보이는 현재 사용자/스토리 뷰어 이름. 없으면 빈 문자열",
  "captionSnippet": "하단 캡션이나 설명문에서 보이는 문장 일부. 없으면 빈 문자열",
  "carouselInfo": "화면에 보이는 1/5, 2/5 같은 슬라이드 번호. 없으면 빈 문자열",
  "platformHint": "instagram|tiktok|youtube|web|unknown",
  "confidence": "high|medium|low"
}

[가장 중요한 규칙]
1. 이미지에 보이지 않는 내용은 절대 추측하지 마.
2. sourceAccount는 반드시 '게시물을 올린 실제 계정명'을 넣어.
3. 인스타그램 캡처에서 화면 상단의 '나', '친구 이름', '사용자 이름', '3주 전', '4일 전'은 viewerAccount 또는 화면 UI일 가능성이 높다.
4. 인스타그램 캡처에서 하단 프로필 사진 옆에 있는 아이디가 실제 게시물 작성자다. 이 값을 sourceAccount로 추출해.
5. 예를 들어 하단에 stay_withyul 이 보이면 sourceAccount는 반드시 "stay_withyul"이다.
6. 예를 들어 하단에 badajour 이 보이면 sourceAccount는 반드시 "badajour"이다.
7. 예를 들어 하단에 nene_weekly 이 보이면 sourceAccount는 반드시 "nene_weekly"이다.
8. 예를 들어 하단에 lilly_yori 이 보이면 sourceAccount는 반드시 "lilly_yori"이다.
9. 상단에 보이는 "나", "지민", "3주 전", "4일 전" 같은 문구를 sourceAccount로 쓰지 마.
10. 이미지 중앙이나 큰 글씨에 있는 문장을 가장 먼저 추출해.
11. 영상 자막처럼 크게 보이는 제목 문구가 있으면 visibleTitle에 그대로 넣어.
12. visibleTitle에는 journal, 사랑과 투쟁!, 통계, 메뉴명 같은 앱 UI/섹션명이 아니라 실제 콘텐츠 제목을 넣어.
13. 번호 목록이 보이면 content에 번호와 문장을 최대한 전부 적어.
14. 예를 들어 1번부터 15번까지 보이면 1번부터 15번까지 모두 적어.
15. 화면 일부가 아이콘에 가려져도 보이는 부분은 적고, 안 보이는 부분은 추측하지 마.
16. 작은 글씨를 모두 못 읽어도 괜찮으니 확실히 보이는 텍스트는 최대한 많이 적어.
17. 흐릿하거나 읽기 어려운 내용은 추측하지 말고 생략해.
18. viewerAccount는 화면 상단에 보이는 현재 사용자/스토리 뷰어 이름이 있을 때만 넣어.
19. captionSnippet은 sourceAccount 아래 또는 옆에 보이는 게시글 설명, 캡션, 릴스 설명 일부를 추출해.
20. carouselInfo는 1/5, 2/5, 3/7, 4/6 같은 슬라이드 번호가 보이면 그대로 추출해.
21. 같은 게시물 분류에 sourceAccount, captionSnippet, carouselInfo가 중요하므로 보이면 반드시 추출해.
22. "좋아요", "댓글", "공유", "저장 필수", "저장해두세요", "프로필 링크", "기다려주세요" 같은 SNS 홍보, 행동 유도 문구는 content와 originalOnlyText에서 제외해.
23. 단, sourceAccount와 captionSnippet은 그룹 분리를 위해 유지해.
24. originalOnlyText에는 sourceAccount, viewerAccount, captionSnippet, carouselInfo, platformHint, confidence 같은 분석용 정보는 넣지 마.
25. originalOnlyText에는 이미지에 보이는 실제 제목과 본문 텍스트만 최대한 그대로 넣어.
26. originalOnlyText는 요약하지 말고 줄바꿈, 번호, 괄호, 시간, 용량을 최대한 유지해.
27. originalOnlyText에 하단 캡션은 넣지 말고, 사진/영상 콘텐츠 안의 본문 텍스트를 우선 넣어.
28. categoryHint는 실제 보이는 내용만 보고 골라.
29. 공부법, 시간관리, 독서, 기록, 목표관리, 생산성, 저축, 재테크, 습관, 삶의 태도는 자기계발. 다이어트 루틴, 식단 관리는 기타로 두고 tags에서 다이어트로 보정하게 한다.
30. 상품 추천, 구매 정보, 할인, 가격 비교, 쇼핑몰, 아이템 추천은 쇼핑.
31. 운동 루틴, 홈트, 헬스, 스트레칭 자체가 핵심이면 운동.
32. 맛집, 카페, 여행지, 전시, 데이트 장소, 방문 장소는 장소.
33. 애매하면 기타.
34. 정보성 본문은 최대한 유지하고, SNS 홍보 문구만 제거해.
""",
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{base64_image}"
                            },
                        },
                    ],
                }
            ],
            temperature=0,
            response_format={"type": "json_object"},
        )

        raw = json.loads(res.choices[0].message.content.strip())

        visible_title = str(raw.get("visibleTitle", "")).strip()
        content = str(raw.get("content", "")).strip()
        original_only_text = str(raw.get("originalOnlyText", "")).strip()
        topic_key = str(raw.get("topicKey", "")).strip()
        category_hint = normalize_category(str(raw.get("categoryHint", "기타")).strip())
        source_account = str(raw.get("sourceAccount", "")).strip()
        viewer_account = str(raw.get("viewerAccount", "")).strip()
        caption_snippet = str(raw.get("captionSnippet", "")).strip()
        carousel_info = str(raw.get("carouselInfo", "")).strip()
        platform_hint = str(raw.get("platformHint", "unknown")).strip()
        confidence = str(raw.get("confidence", "medium")).strip()

        analysis_parts = []
        original_parts = []

        if visible_title:
            analysis_parts.append(f"제목: {visible_title}")

        if topic_key:
            analysis_parts.append(f"주제키: {topic_key}")

        if source_account:
            analysis_parts.append(f"sourceAccount: {source_account}")

        if viewer_account:
            analysis_parts.append(f"viewerAccount: {viewer_account}")

        if caption_snippet:
            analysis_parts.append(f"captionSnippet: {caption_snippet}")

        if carousel_info:
            analysis_parts.append(f"carouselInfo: {carousel_info}")

        analysis_parts.append(f"platformHint: {platform_hint}")
        analysis_parts.append(f"분류힌트: {category_hint}")
        analysis_parts.append(f"신뢰도: {confidence}")

        if content:
            analysis_parts.append(f"내용:\n{content}")

        if original_only_text:
            original_parts.append(original_only_text)
        else:
            if visible_title:
                original_parts.append(visible_title)
            if content:
                original_parts.append(content)

        analysis_text = "\n".join(analysis_parts).strip()
        original_text = "\n".join(original_parts).strip()

        return {
            "analysisText": clean_analysis_text(analysis_text),
            "originalOnlyText": clean_display_original_text(original_text),
        }

    except Exception as e:
        print("Image OCR error:", e)
        return {
            "analysisText": "이미지 텍스트 추출 중 오류가 발생했습니다.",
            "originalOnlyText": "이미지 텍스트 추출 중 오류가 발생했습니다.",
        }


async def extract_texts_from_uploaded_images(files: List[UploadFile]) -> Tuple[List[str], List[str]]:
    semaphore = asyncio.Semaphore(OCR_PARALLEL_LIMIT)

    async def process_one_image(index: int, file: UploadFile):
        async with semaphore:
            try:
                image_bytes = await file.read()
                base64_img = base64.b64encode(image_bytes).decode("utf-8")

                extracted = await asyncio.to_thread(
                    extract_image_text,
                    base64_img,
                )

                analysis_text = extracted.get("analysisText", "")
                original_only_text = extracted.get("originalOnlyText", "")

                return index, {
                    "analysisText": f"[이미지 {index + 1}]\n{analysis_text}".strip(),
                    "originalOnlyText": f"[이미지 {index + 1}]\n{original_only_text}".strip(),
                }

            except Exception as e:
                print(f"Image {index + 1} process error:", e)
                return index, {
                    "analysisText": f"[이미지 {index + 1}]\n이미지 텍스트 추출 중 오류가 발생했습니다.",
                    "originalOnlyText": f"[이미지 {index + 1}]\n이미지 텍스트 추출 중 오류가 발생했습니다.",
                }

    tasks = [
        process_one_image(i, file)
        for i, file in enumerate(files)
    ]

    results = await asyncio.gather(*tasks)
    results.sort(key=lambda item: item[0])

    analysis_texts = [item["analysisText"] for _, item in results]
    original_texts = [item["originalOnlyText"] for _, item in results]

    return analysis_texts, original_texts


def build_fail_response(
    url: str,
    title: str,
    summary: str,
    content_type: str,
    tags=None,
    original_text="",
):
    safe_tags = normalize_tags(tags or [])

    if not safe_tags:
        safe_tags = ["이미지"] if content_type in ["image", "screenshots"] else ["링크"]

    return {
        "status": "FAIL",
        "url": url,
        "title": title,
        "summary": summary,
        "shortSummary": summary,
        "detailSummary": summary,
        "category": "기타",
        "tags": safe_tags,
        "thumbnail": "",
        "originalText": original_text,
        "contentType": content_type,
    }


@app.post("/analyze")
def analyze_url(url: str):
    try:
        if "instagram.com" in url:
            _, content, thumbnail = get_instagram_data(url)
        else:
            _, content, thumbnail = get_web_data(url)

        if not content or content == "내용 없음":
            result = build_fail_response(
                url=url,
                title="콘텐츠 로드 실패",
                summary="링크에서 본문 내용을 가져오지 못했습니다.",
                content_type="link",
                tags=["링크"],
                original_text="내용 없음",
            )
            result["thumbnail"] = thumbnail
            return result

        ai_title, summary, short_summary, category, tags = get_ai_summary(content)

        if ai_title == "분석 실패":
            result = build_fail_response(
                url=url,
                title="AI 요약 실패",
                summary="AI 분석 중 오류가 발생했습니다.",
                content_type="link",
                tags=["링크"],
                original_text=content,
            )
            result["thumbnail"] = thumbnail
            return result

        return {
            "status": "ACTIVE",
            "url": url,
            "title": ai_title,
            "summary": summary,
            "shortSummary": short_summary,
            "detailSummary": summary,
            "category": category,
            "tags": tags if tags else ["링크"],
            "thumbnail": thumbnail,
            "originalText": content,
            "contentType": "link",
        }

    except Exception as e:
        print(f"Global analyze error: {e}")

        return build_fail_response(
            url=url,
            title="시스템 오류",
            summary="서버 내부 에러가 발생했습니다.",
            content_type="link",
            tags=["링크"],
            original_text="에러 발생",
        )


@app.post("/analyze/image")
async def analyze_image(files: List[UploadFile] = File(...)):
    try:
        if not files or (len(files) == 1 and files[0].filename == ""):
            return build_fail_response(
                url="uploaded_file",
                title="이미지 업로드 실패",
                summary="첨부된 이미지 파일이 없습니다.",
                content_type="image",
                tags=["이미지"],
                original_text="파일 없음",
            )

        image_texts, original_texts = await extract_texts_from_uploaded_images(files)
        all_text = "\n\n".join(image_texts).strip()
        original_all_text = "\n\n".join(original_texts).strip()

        ai_title, summary, short_summary, category, tags = get_ai_summary(all_text)

        is_long_multi_image_text = (
            len(files) >= 3
            and len(original_all_text) >= 800
        )

        if is_long_multi_image_text:
            summary = build_preserved_summary_from_original_text(original_all_text)
            short_summary = make_short_summary_from_preserved_text(original_all_text)
        elif is_text_heavy_numbered_content(original_all_text):
            summary = clean_original_for_summary(original_all_text)
            short_summary = make_short_summary_from_original_text(original_all_text)
       
        if ai_title == "분석 실패":
            return build_fail_response(
                url="uploaded_file",
                title="AI 이미지 요약 실패",
                summary="이미지 분석 중 오류가 발생했습니다.",
                content_type="image",
                tags=["이미지"],
                original_text=original_all_text,
            )

        return {
            "status": "ACTIVE",
            "url": "uploaded_file",
            "title": ai_title,
            "summary": summary,
            "shortSummary": short_summary,
            "detailSummary": summary,
            "category": category,
            "tags": tags if tags else ["이미지"],
            "thumbnail": "",
            "originalText": original_all_text,
            "contentType": "image",
        }

    except Exception as e:
        print(f"Global image analyze error: {e}")

        return build_fail_response(
            url="uploaded_file",
            title="시스템 오류",
            summary="이미지 처리 중 서버 내부 에러가 발생했습니다.",
            content_type="image",
            tags=["이미지"],
            original_text="에러 발생",
        )


@app.post("/analyze/image-groups")
async def analyze_image_groups(files: List[UploadFile] = File(...)):
    try:
        if not files or (len(files) == 1 and files[0].filename == ""):
            return {
                "status": "FAIL",
                "groups": [
                    {
                        "url": "uploaded_image",
                        "title": "이미지 업로드 실패",
                        "summary": "첨부된 이미지 파일이 없습니다.",
                        "shortSummary": "첨부된 이미지 파일이 없습니다.",
                        "detailSummary": "첨부된 이미지 파일이 없습니다.",
                        "category": "기타",
                        "tags": ["이미지"],
                        "thumbnail": "",
                        "status": "FAILED",
                        "originalText": "파일 없음",
                        "imageIndexes": [],
                    }
                ],
            }

        image_texts, original_texts = await extract_texts_from_uploaded_images(files)

        all_text = "\n\n".join(image_texts).strip()
        original_all_text = "\n\n".join(original_texts).strip()

        ai_title, summary, short_summary, category, tags = get_ai_summary(all_text)

        is_long_multi_image_text = (
            len(files) >= 3
            and len(original_all_text) >= 800
        )

        if is_long_multi_image_text:
            summary = build_preserved_summary_from_original_text(original_all_text)
            short_summary = make_short_summary_from_preserved_text(original_all_text)
        elif is_text_heavy_numbered_content(original_all_text):
            summary = clean_original_for_summary(original_all_text)
            short_summary = make_short_summary_from_original_text(original_all_text)

        if ai_title == "분석 실패":
            group = {
                "url": "uploaded_image",
                "title": "스크린샷 분석 결과",
                "summary": "이미지 내용을 하나의 카드로 저장했습니다.",
                "shortSummary": "이미지 내용을 저장했습니다.",
                "detailSummary": "이미지 내용을 하나의 카드로 저장했습니다.",
                "category": "기타",
                "tags": ["이미지"],
                "thumbnail": "",
                "status": "FAILED",
                "originalText": original_all_text,
                "imageIndexes": list(range(len(image_texts))),
            }
        else:
            group = {
                "url": "uploaded_image",
                "title": ai_title,
                "summary": summary,
                "shortSummary": short_summary,
                "detailSummary": summary,
                "category": category,
                "tags": tags if tags else ["이미지"],
                "thumbnail": "",
                "status": "COMPLETED",
                "originalText": original_all_text,
                "imageIndexes": list(range(len(image_texts))),
            }

        return {
            "status": "ACTIVE",
            "groups": [group],
        }

    except Exception as e:
        print(f"Global image groups analyze error: {e}")

        return {
            "status": "FAIL",
            "groups": [
                {
                    "url": "uploaded_image",
                    "title": "시스템 오류",
                    "summary": "이미지 그룹 분석 중 서버 내부 에러가 발생했습니다.",
                    "shortSummary": "이미지 그룹 분석 중 서버 내부 에러가 발생했습니다.",
                    "detailSummary": "이미지 그룹 분석 중 서버 내부 에러가 발생했습니다.",
                    "category": "기타",
                    "tags": ["이미지"],
                    "thumbnail": "",
                    "status": "FAILED",
                    "originalText": str(e),
                    "imageIndexes": [],
                }
            ],
        }

@app.post("/analyze/complex")
async def analyze_complex(url: str, files: List[UploadFile] = File(...)):
    try:
        if "instagram.com" in url:
            _, url_content, thumbnail = get_instagram_data(url)
        else:
            _, url_content, thumbnail = get_web_data(url)

        image_texts = []
        original_texts = []

        if files and files[0].filename != "":
            image_texts, original_texts = await extract_texts_from_uploaded_images(files)

        image_text = "\n\n".join(image_texts).strip()
        original_image_text = "\n\n".join(original_texts).strip()
        combined = f"[링크 정보]\n{url_content}\n\n[이미지 텍스트]\n{image_text}".strip()
        original_combined = f"[링크 정보]\n{url_content}\n\n[이미지 원본 글]\n{original_image_text}".strip()

        ai_title, summary, short_summary, category, tags = get_ai_summary(combined)

        if ai_title == "분석 실패":
            result = build_fail_response(
                url=url,
                title="AI 복합 요약 실패",
                summary="복합 콘텐츠 분석 중 오류가 발생했습니다.",
                content_type="complex",
                tags=["링크", "이미지"],
                original_text=original_combined,
            )
            result["thumbnail"] = thumbnail
            return result

        return {
            "status": "ACTIVE",
            "url": url,
            "title": ai_title,
            "summary": summary,
            "shortSummary": short_summary,
            "detailSummary": summary,
            "category": category,
            "tags": tags if tags else ["링크", "이미지"],
            "thumbnail": thumbnail,
            "originalText": original_combined,
            "contentType": "complex",
        }

    except Exception as e:
        print(f"Global complex analyze error: {e}")

        return build_fail_response(
            url=url,
            title="시스템 오류",
            summary="복합 분석 중 서버 내부 에러가 발생했습니다.",
            content_type="complex",
            tags=["링크", "이미지"],
            original_text="에러 발생",
        )


@app.post("/upload/images")
async def upload_images(request: Request, files: List[UploadFile] = File(...)):
    urls = []

    for file in files:
        contents = await file.read()

        extension = os.path.splitext(file.filename or "")[1].lower()

        if not extension:
            extension = ".jpg"

        filename = f"{uuid4().hex}{extension}"

        with open(UPLOAD_DIR / filename, "wb") as f:
            f.write(contents)

        urls.append(f"{str(request.base_url).rstrip('/')}/uploads/{filename}")

    return {
        "status": "success",
        "imageUrls": urls,
    }


@app.get("/")
def health():
    return {"status": "ok"}