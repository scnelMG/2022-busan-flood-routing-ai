# 사용 가이드

## 1. 환경 준비

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## 2. 입력 데이터 준비

이 저장소는 데이터 파일을 제공하지 않습니다. 적법한 접근 권한과 재배포 검토를 마친 뒤에만, 개인 작업 공간에 다음 파일을 준비하세요.

```text
data/private/flood_features.csv
data/private/road_edges.csv
```

두 파일의 필요한 열은 [데이터 출처와 공개 경계](data-sources.md)에 정의되어 있습니다. `data/private/`는 `.gitignore`에 포함되어 있으므로 Git에 추가하지 마세요.

## 3. 노트북 실행

```powershell
jupyter notebook notebooks/flood-routing-modeling.ipynb
```

위에서 아래로 실행합니다.

1. 입력 파일과 열을 검증합니다.
2. 학습/검증 분할, 스케일링, 학습 데이터 전용 SMOTE를 수행합니다.
3. 랜덤 포레스트 분류 모델을 학습하고, 별도 검증 데이터에서 지표를 계산합니다.
4. 침수 상태가 포함된 도로 링크를 읽고 Q-learning 예제를 실행합니다.

입력 데이터가 없으면 첫 데이터 로드 단계에서 의도적으로 중단됩니다. 공개본에 샘플 데이터를 추가하거나, 실행 결과를 공개하지 마세요.

## 4. 공개 전 점검

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate-public-release.ps1
```

이 스크립트는 공개 후보 파일에서 비공개 경로·금지 확장자·개인 경로·출력성 이미지/긴 인코딩 페이로드를 확인합니다. 별도 입력으로 금지 경로를 주어 거부 동작도 확인할 수 있습니다.
