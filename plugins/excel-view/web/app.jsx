import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Workbook } from '@fortune-sheet/react';
import {
  FortuneExcelHelper,
  transformExcelToFortune,
  transformFortuneToExcel,
} from '@corbe30/fortune-excel';
import '@fortune-sheet/react/dist/index.css';

const params = new URLSearchParams(window.location.search);
const filePath = params.get('path') || '';
const fileName = filePath.split(/[\\/]/).pop() || 'workbook.xlsx';
const fileUrl = `${window.location.origin}/file?path=${encodeURIComponent(filePath)}`;

function ExcelApp() {
  const [sheets, setSheets] = useState([{ name: 'Sheet1' }]);
  const [workbookKey, setWorkbookKey] = useState(0);
  const [state, setState] = useState('Loading workbook...');
  const [error, setError] = useState('');
  const sheetRef = useRef(null);

  const loadWorkbook = useCallback(async () => {
    setError('');
    setState('Loading workbook...');
    try {
      const response = await fetch(fileUrl);
      if (!response.ok) throw new Error(`Could not read ${fileName}`);
      const blob = await response.blob();
      const file = new File([blob], fileName, {
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
      await transformExcelToFortune(file, setSheets, setWorkbookKey, sheetRef);
      setState('Workbook loaded');
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : String(cause);
      setError(`Unable to open ${fileName}\n${message}`);
      setState('Load failed');
    }
  }, []);

  useEffect(() => { void loadWorkbook(); }, [loadWorkbook]);
  useEffect(() => {
    document.title = fileName;
    document.getElementById('file-name').textContent = fileName;
    document.getElementById('file-state').textContent = state;
    document.getElementById('error').hidden = !error;
    document.getElementById('error').textContent = error;
  }, [error, state]);

  useEffect(() => {
    const reload = document.getElementById('reload-button');
    const exportButton = document.getElementById('export-button');
    const onReload = () => { void loadWorkbook(); };
    const onExport = async () => {
      try {
        await transformFortuneToExcel(sheetRef, 'xlsx', true);
      } catch (cause) {
        setError(`Unable to export ${fileName}\n${cause instanceof Error ? cause.message : cause}`);
      }
    };
    reload.addEventListener('click', onReload);
    exportButton.addEventListener('click', onExport);
    return () => {
      reload.removeEventListener('click', onReload);
      exportButton.removeEventListener('click', onExport);
    };
  }, [loadWorkbook]);

  useEffect(() => {
    document.getElementById('export-button').disabled = !sheetRef.current;
  }, [workbookKey]);

  return <>
    <FortuneExcelHelper
      setKey={setWorkbookKey}
      setSheets={setSheets}
      sheetRef={sheetRef}
      config={{ import: { xlsx: true, csv: false }, export: { xlsx: true, csv: false } }}
    />
    <Workbook key={workbookKey} data={sheets} ref={sheetRef} allowEdit={false} />
  </>;
}

createRoot(document.getElementById('app')).render(<ExcelApp />);
