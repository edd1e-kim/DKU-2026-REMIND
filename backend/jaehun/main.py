from fastapi import FastAPI, UploadFile, File, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import requests
from bs4 import BeautifulSoup
import os
import re
import json
import base64
from typing import List
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


def clean_ocr_text(text: str) -> str:
    if not text:
        return ""

    text = text.replace("\r\n", "\n")

    text = re.sub(r"```[a-zA-Z]*", "", text)
    text = text.replace("```", "")
    text = text.replace("`", "")

    cleaned_lines = []

    for line in text.split("\n"):
        line = line.strip()

        if not line:
            cleaned_lines.append("")
            continue

        if line.lower() in ["matomag"]:
            continue

        cleaned_lines.append(line)

    text = "\n".join(cleaned_lines)
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()


def is_numbered_summary(summary: str) -> bool:
    circled_numbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]
    return any(num in summary for num in circled_numbers)


def clean_summary_text(summary: str) -> str:
    if not summary:
        return ""

    summary = summary.replace("\r\n", "\n")
    summary = summary.replace("```", "").replace("`", "")
    summary = summary.strip()

    circled_numbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]

    # ① ② ③이 한 줄에 붙어서 오면 강제로 줄바꿈
    for num in circled_numbers:
        summary = summary.replace(f" {num}", f"\n{num}")

    raw_lines = summary.split("\n")
    lines = []

    numbered_mode = is_numbered_summary(summary)

    for raw_line in raw_lines:
        line = raw_line.strip()

        if not line:
            continue

        line = line.replace("•", "").strip()
        line = line.lstrip("-").strip()

        # 1. 2. 3. 같은 일반 번호 제거
        line = re.sub(r"^\d+[\).\s]+", "", line).strip()

        if numbered_mode:
            has_circled = any(line.startswith(num) for num in circled_numbers)

            if not has_circled:
                index = len(lines)
                if index < len(circled_numbers):
                    line = f"{circled_numbers[index]} {line}"

            lines.append(line)
        else:
            if not line.startswith("•"):
                line = f"• {line}"

            lines.append(line)

    if numbered_mode:
        return "\n".join(lines[:10])

    return "\n".join(lines[:5])


def get_ai_summary(content: str):
    if not content or content == "내용 없음" or len(content.strip()) < 10:
        return "제목 없음", "정보를 추출할 본문이 부족합니다.", "기타", ["내용부족"]

    try:
        prompt = f"""
너는 저장형 콘텐츠 앱 ReSee의 요약 전문가야.
아래 본문을 한국어로 분석해서 반드시 JSON만 반환해.

[출력 JSON 형식]
{{
  "title": "제목",
  "summary": "요약",
  "category": "카테고리",
  "tags": ["태그1", "태그2", "태그3"]
}}

[title 규칙]
1. 본문 내용을 대표하는 자연스러운 제목
2. 원문에 핵심 제목이 보이면 최대한 그 제목을 살려서 작성
3. 목록형 콘텐츠면 "TOP 10", "10가지", "방법", "습관", "체크리스트", "루틴" 같은 핵심 표현을 제목에 포함
4. 15~35자 정도로 작성
5. 너무 짧고 추상적인 제목 금지
6. 이미지 첫 장에 큰 제목이 있으면 그 제목을 우선 반영
7. 제목은 사용자가 나중에 봤을 때 내용이 바로 떠오르게 작성
8. 과장된 내용을 새로 만들지는 말 것
9. 예: "100일만 반복하면 인생이 바뀌는 습관 TOP 10"
10. 예: "부정적 생각 다루는 8가지 방법"
11. 예: "매력적인 핑크 백팩 추천 모음"

[summary 핵심 규칙]
1. 중요한 정보는 빠뜨리지 말 것.
2. OCR 원문을 그대로 복사하지 말고 의미를 정리할 것.
3. 가격, 상품명, 장소명, 날짜, 개수, 순서, 핵심 행동은 유지할 것.
4. 없는 내용은 지어내지 말 것.
5. 같은 의미를 반복하지 말 것.
6. 절대 중간에 ...으로 줄이지 말 것.
7. 항목끼리는 반드시 줄바꿈할 것.

[목록형 콘텐츠 요약 규칙]
1. 원문이 "TOP 10", "10가지", "5가지", "체크리스트", "방법", "습관", "순서", "루틴"처럼 목록형 콘텐츠면 번호형 요약으로 작성.
2. 번호형 요약은 반드시 ① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩ 형식을 사용.
3. 원문이 10가지면 가능한 한 10개를 모두 유지.
4. 원문이 5가지면 5개를 유지.
5. 각 항목은 반드시 줄바꿈해서 작성.
6. 각 항목은 "① 항목: 설명" 형식으로 작성.
7. 설명은 핵심 의미가 빠지지 않을 정도로 자연스럽게 작성.
8. 한 줄에 여러 번호를 붙여 쓰지 말 것.

[일반 콘텐츠 요약 규칙]
1. 목록형 콘텐츠가 아니면 핵심만 3~5개 요약.
2. 일반 요약은 "• 항목: 설명" 형식 사용.
3. 각 항목은 반드시 줄바꿈해서 작성.
4. 너무 긴 문장 금지.
5. 쉼표로 길게 이어 쓰지 말 것.

[상품 콘텐츠 요약 규칙]
1. 상품이 여러 개 나오면 상품별로 요약.
2. 상품명, 가격, 핵심 특징을 최대한 유지.
3. 상품이 3개 이상이면 3~5개까지 요약.
4. 상품 요약은 "• 상품명: 가격/특징" 형식 사용.

[category 규칙]
1. 반드시 아래 중 하나만 선택.
2. 장소, 자기계발, 쇼핑, 운동, 기타

[tags 규칙]
1. 짧은 키워드 2~3개
2. # 없이 단어만 작성
3. 너무 일반적인 단어 금지

[좋은 title 예시]
100일만 반복하면 인생이 바뀌는 습관 TOP 10
부정적 생각 다루는 8가지 방법
매력적인 핑크 백팩 추천 모음
하루를 바꾸는 작은 루틴 모음

[나쁜 title 예시]
100일 습관
삶 변화
이미지 분석 결과
자기계발 정보
좋은 습관

[좋은 summary 예시 - 10가지 목록형]
① 하루 10분 독서: 짧게라도 꾸준히 읽기
② 10분 운동: 가벼운 움직임으로 몸 깨우기
③ 하루 계획: 오늘 할 일을 먼저 정리하기
④ 짧게 글쓰기: 생각을 문장으로 정리하기
⑤ 목표 매일 보기: 방향을 계속 확인하기
⑥ 감사 기록: 좋은 일에 집중하기
⑦ 핸드폰 줄이기: 집중할 시간 확보하기
⑧ 하루 돌아보기: 성장한 점 확인하기
⑨ 필요한 일 줄이기: 중요한 일에 집중하기
⑩ 새로운 것 배우기: 매일 조금씩 성장하기

[좋은 summary 예시 - 일반 자기계발]
• 짧은 독서: 하루 10분으로 생각을 확장
• 작은 운동: 가벼운 움직임으로 몸을 깨움
• 하루 계획: 목표를 정해 방향을 잡음

[좋은 summary 예시 - 쇼핑]
• 노이아고 백팩: 5만원대 가성비 제품
• 미닛뮤트 백팩: 초경량 핑크 컬러
• 스커프터 백팩: 핑크와 브라운 조합

[나쁜 summary 예시]
• 하루 10분 독서: 짧은 시간이라도 꾸준히 읽으면 지식이 쌓이고 생각의 깊이가 달라짐, 10분 운동: 가벼운 움직임으로 몸과 정신이 깨어남
• ① 하루 10분 독서 ② 짧게 글쓰기 ③ 하루 계획 세우기
• 이미지에 있는 내용을 모두 길게 나열한 문장
• 원문을 그대로 복사한 문장
• 중요한 목록 10개 중 3개만 남긴 요약
• 중간에 ...으로 끊긴 요약

본문:
{content[:4000]}
"""

        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "system",
                    "content": "너는 JSON만 반환하는 저장형 콘텐츠 요약기야.",
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
        summary = str(res.get("summary", "")).strip()
        category = str(res.get("category", "기타")).strip()
        tags = res.get("tags", [])

        allowed_categories = ["장소", "자기계발", "쇼핑", "운동", "기타"]
        if category not in allowed_categories:
            category = "기타"

        if not isinstance(tags, list):
            tags = []

        tags = [
            str(tag).replace("#", "").strip()
            for tag in tags
            if str(tag).replace("#", "").strip()
        ][:3]

        summary = clean_summary_text(summary)

        return title, summary, category, tags

    except Exception as e:
        print("AI summary error:", e)
        return "분석 실패", "내용 요약 중 에러 발생", "기타", ["에러"]


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
        # [네이버 블로그 iframe 크롤링 방어 로직]
        if "blog.naver.com" in url and "PostView.naver" not in url:
            # 일반 주소 패턴(blog.naver.com/아이디/글번호)에서 데이터 추출
            match = re.search(r"blog\.naver\.com/([A-Za-z0-9_-]+)/(\d+)", url)
            if match:
                blog_id = match.group(1)
                log_no = match.group(2)
                # 실제 텍스트 내용이 날것으로 들어있는 진짜 알맹이 주소로 변환
                url = f"https://blog.naver.com/PostView.naver?blogId={blog_id}&logNo={log_no}"

        # 봇(Bot) 차단을 우회하기 위해 User-Agent를 조금 더 명확하게 명시
        res = requests.get(
            url,
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
            timeout=10,
        )

        soup = BeautifulSoup(res.text, "html.parser")

        # 네이버 블로그의 실제 글 제목은 og:title 메타태그에 가장 정확하게 들어있습니다.
        og_title = soup.find("meta", property="og:title")
        title = og_title.get("content").strip() if og_title else (soup.title.string.strip() if soup.title else "제목 없음")

        body = ""
        if soup.body:
            # 네이버 스마트에디터 ONE 본문 영역 (.se-main-container)을 우선 탐색하여 광고/댓글 레이아웃 제외
            naver_content = soup.find(class_="se-main-container") or soup.find(id="postViewArea")
            if naver_content:
                body = naver_content.get_text(separator="\n", strip=True)[:3000]
            else:
                body = soup.body.get_text(separator="\n", strip=True)[:3000]

        og = soup.find("meta", property="og:image")
        thumbnail = og.get("content") if og else ""

        return title, body or "내용 없음", thumbnail

    except Exception as e:
        print("Web data error:", e)
        return "제목 없음", "내용 없음", ""


def extract_image_text(base64_image: str):
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
이미지 안의 텍스트와 핵심 정보를 한국어로 정리해줘.

규칙:
1. 절대 ``` 코드블록을 쓰지 마.
2. 마크다운 형식을 쓰지 마.
3. 이미지에 보이는 상품명, 가격, 핵심 설명을 줄바꿈으로 정리해.
4. matomag 같은 반복 출처/계정명은 제외해.
5. 없는 내용은 지어내지 마.
6. 결과는 순수 텍스트만 반환해.
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
        )

        return clean_ocr_text(res.choices[0].message.content)

    except Exception as e:
        print("Image OCR error:", e)
        return "이미지 텍스트 추출 중 오류가 발생했습니다."


@app.post("/analyze")
def analyze_url(url: str):
    try:
        if "instagram.com" in url:
            _, content, thumbnail = get_instagram_data(url)
        else:
            _, content, thumbnail = get_web_data(url)

        # [방어 로직] 스크래핑 자체가 실패해서 본문이 없을 때
        if not content or content == "내용 없음":
            return {
                "status": "FAIL",
                "url": url,
                "title": "콘텐츠 로드 실패",
                "summary": "링크에서 본문 내용을 가져오지 못했습니다.",
                "category": "기타",
                "tags": ["실패"],
                "thumbnail": thumbnail,
                "originalText": "내용 없음",
                "contentType": "link",
            }

        ai_title, summary, category, tags = get_ai_summary(content)

        # [방어 로직] 스크래핑은 성공했으나 AI 요약에서 에러가 났을 때
        if ai_title == "분석 실패":
            return {
                "status": "FAIL",
                "url": url,
                "title": "AI 요약 실패",
                "summary": "AI 분석 중 오류가 발생했습니다.",
                "category": "기타",
                "tags": ["실패"],
                "thumbnail": thumbnail,
                "originalText": content,  # 지민님 요청: 원본 기록(텍스트)은 유지해서 반환
                "contentType": "link",
            }

        return {
            "status": "ACTIVE",
            "url": url,
            "title": ai_title,
            "summary": summary,
            "category": category,
            "tags": tags,
            "thumbnail": thumbnail,
            "originalText": content,
            "contentType": "link",
        }
    except Exception as e:
        print(f"Global analyze error: {e}")
        return {
            "status": "FAIL",
            "url": url,
            "title": "시스템 오류",
            "summary": "서버 내부 에러가 발생했습니다.",
            "category": "기타",
            "tags": ["에러"],
            "thumbnail": "",
            "originalText": "에러 발생",
            "contentType": "link",
        }


@app.post("/analyze/image")
async def analyze_image(files: List[UploadFile] = File(...)):
    try:
        # [방어 로직] 파일이 아예 첨부되지 않았을 때
        if not files or (len(files) == 1 and files[0].filename == ""):
            return {
                "status": "FAIL",
                "url": "uploaded_file",
                "title": "이미지 업로드 실패",
                "summary": "첨부된 이미지 파일이 없습니다.",
                "category": "기타",
                "tags": ["실패"],
                "thumbnail": "",
                "originalText": "파일 없음",
                "contentType": "image",
            }

        image_texts = []
        for i, file in enumerate(files, 1):
            base64_img = base64.b64encode(await file.read()).decode("utf-8")
            extracted_text = extract_image_text(base64_img)
            image_texts.append(f"[이미지 {i}]\n{extracted_text}")

        all_text = "\n\n".join(image_texts).strip()
        ai_title, summary, category, tags = get_ai_summary(all_text)

        # AI 분석 실패 시 처리
        if ai_title == "분석 실패":
            return {
                "status": "FAIL",
                "url": "uploaded_file",
                "title": "AI 이미지 요약 실패",
                "summary": "이미지 분석 중 오류가 발생했습니다.",
                "category": "기타",
                "tags": ["실패"],
                "thumbnail": "",
                "originalText": all_text,  # 원본 추출 텍스트는 보존
                "contentType": "image",
            }

        return {
            "status": "ACTIVE",
            "url": "uploaded_file",
            "title": ai_title,
            "summary": summary,
            "category": category,
            "tags": tags,
            "thumbnail": "",
            "originalText": all_text,
            "contentType": "image",
        }
    except Exception as e:
        print(f"Global image analyze error: {e}")
        return {
            "status": "FAIL",
            "url": "uploaded_file",
            "title": "시스템 오류",
            "summary": "이미지 처리 중 서버 내부 에러가 발생했습니다.",
            "category": "기타",
            "tags": ["에러"],
            "thumbnail": "",
            "originalText": "에러 발생",
            "contentType": "image",
        }


@app.post("/analyze/complex")
async def analyze_complex(url: str, files: List[UploadFile] = File(...)):
    try:
        if "instagram.com" in url:
            _, url_content, thumbnail = get_instagram_data(url)
        else:
            _, url_content, thumbnail = get_web_data(url)

        image_texts = []
        # 파일이 존재할 때만 OCR 진행
        if files and files[0].filename != "":
            for i, file in enumerate(files, 1):
                base64_img = base64.b64encode(await file.read()).decode("utf-8")
                extracted_text = extract_image_text(base64_img)
                image_texts.append(f"[이미지 {i}]\n{extracted_text}")

        image_text = "\n\n".join(image_texts).strip()
        combined = f"[링크 정보]\n{url_content}\n\n[이미지 텍스트]\n{image_text}".strip()

        ai_title, summary, category, tags = get_ai_summary(combined)

        if ai_title == "분석 실패":
            return {
                "status": "FAIL",
                "url": url,
                "title": "AI 복합 요약 실패",
                "summary": "복합 콘텐츠 분석 중 오류가 발생했습니다.",
                "category": "기타",
                "tags": ["실패"],
                "thumbnail": thumbnail,
                "originalText": combined,
                "contentType": "complex",
            }

        return {
            "status": "ACTIVE",
            "url": url,
            "title": ai_title,
            "summary": summary,
            "category": category,
            "tags": tags,
            "thumbnail": thumbnail,
            "originalText": combined,
            "contentType": "complex",
        }
    except Exception as e:
        print(f"Global complex analyze error: {e}")
        return {
            "status": "FAIL",
            "url": url,
            "title": "시스템 오류",
            "summary": "복합 분석 중 서버 내부 에러가 발생했습니다.",
            "category": "기타",
            "tags": ["에러"],
            "thumbnail": "",
            "originalText": "에러 발생",
            "contentType": "complex",
        }


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