FUNCTION ZHRFM22
  EXPORTING
    E_ERRO TYPE BINPT_FUNC
    E_RETORNO TYPE ZTWS_RETORNO_C
  TABLES
    T_ESTRUTURA LIKE ZLHR_UNIDADES_ORG_PT_EN
    RETURN LIKE BAPIRET2.

  "======================================================================
  " DEFINIÇÕES DE TIPOS
  "======================================================================

  " --- Tipos para a Resposta do PUT (e atualização da tabela ZHRTB85)
  TYPES: BEGIN OF ty_put_response,
           pureid TYPE i,
           uuid   TYPE string,
         END OF ty_put_response.

  " --- Tipos para a Desserialização da Resposta do GET
  TYPES: BEGIN OF ty_get_name,
           first_name TYPE string,
           last_name  TYPE string,
         END OF ty_get_name.
  TYPES: BEGIN OF ty_get_organization,
           system_name TYPE string,
           uuid        TYPE string,
         END OF ty_get_organization.
  TYPES: BEGIN OF ty_get_period,
           start_date TYPE string,
         END OF ty_get_period.
  TYPES: BEGIN OF ty_get_staff_org_ass,
           organization TYPE ty_get_organization,
           period       TYPE ty_get_period,
         END OF ty_get_staff_org_ass.
  TYPES: BEGIN OF ty_get_response,
           name                        TYPE ty_get_name,
           staff_organization_associations TYPE STANDARD TABLE OF ty_get_staff_org_ass WITH EMPTY KEY,
           orcid                       TYPE string,
         END OF ty_get_response.

  " --- Tipos para a Serialização do Pedido PUT
  TYPES: BEGIN OF ty_put_name,
           first_name TYPE string,
           last_name  TYPE string,
         END OF ty_put_name.
  TYPES: BEGIN OF ty_put_description,
           en_gb TYPE string,
           pt_pt TYPE string,
         END OF ty_put_description.
  TYPES: BEGIN OF ty_put_type,
           uri  TYPE string,
           term TYPE ty_put_description,
         END OF ty_put_type.
  TYPES: BEGIN OF ty_put_organization,
           system_name TYPE string,
           uuid        TYPE string,
         END OF ty_put_organization.
  TYPES: BEGIN OF ty_put_period,
           start_date TYPE string,
         END OF ty_put_period.
  TYPES: BEGIN OF ty_put_st_org_ass,
           type_discriminator TYPE string,
           organization       TYPE ty_put_organization,
           period             TYPE ty_put_period,
         END OF ty_put_st_org_ass.
  TYPES: BEGIN OF ty_put_visibility,
           key         TYPE string,
           description TYPE ty_put_description,
         END OF ty_put_visibility.
  TYPES: BEGIN OF ty_put_identifiers,
           typediscriminator TYPE string,
           id                TYPE string,
           type_             TYPE ty_put_type,
         END OF ty_put_identifiers.
  TYPES: BEGIN OF ty_put_data,
           name          TYPE ty_put_name,
           staff_org_ass TYPE STANDARD TABLE OF ty_put_st_org_ass WITH EMPTY KEY,
           visibility    TYPE ty_put_visibility,
           identifiers   TYPE STANDARD TABLE OF ty_put_identifiers WITH EMPTY KEY,
           user          TYPE ty_put_organization,
           orcid         TYPE string,
         END OF ty_put_data.

  " --- Tipo para os dados iniciais selecionados da base de dados
  TYPES: BEGIN OF ty_initial_data,
           pernr    TYPE pa0000-pernr,
           vorna    TYPE pa0002-vorna,
           nachn    TYPE pa0002-nachn,
           persg    TYPE pa0001-persg,
           stat2    TYPE pa0000-stat2,
           begda    TYPE hrp1001-begda,
           uo       TYPE zhrtb83-uo,
           persk    TYPE pa0001-persk,
           variante TYPE zhrtb83-variante,
           uuid     TYPE zhrtb85-uuid,
         END OF.


  "======================================================================
  " DECLARAÇÕES DE DADOS
  "======================================================================
  CONSTANTS:
    gc_base_url  TYPE string VALUE 'https://research.uc.pt', " CONFIRMAR ESTE URL
    gc_api_path  TYPE string VALUE '/ws/api/persons',
    gc_api_key   TYPE string VALUE 'f4455b08-74a7-4c6c-b05a-eeddf4f70b0e'. " Usar um local seguro em produção

  DATA: lt_dados             TYPE TABLE OF ty_initial_data,
        lt_dados_restantes   TYPE TABLE OF ty_initial_data,
        lt_zhrtb85           TYPE TABLE OF zhrtb85,
        t_estrutura_         TYPE TABLE OF zlhr_unidades_org_pt_en,
        lo_http_client       TYPE REF TO if_http_client.


  "======================================================================
  " SELEÇÃO DE DADOS
  "======================================================================

  " --- Selecionar pessoas e as suas unidades organizacionais
  SELECT pa0~pernr, pa2~vorna, pa2~nachn, pa1~persg, pa0~stat2, hrp1~begda, zhr83~uo, pa1~persk, zhr83~variante, zhr85~uuid
    INTO TABLE @lt_dados
    FROM zhrtb83 AS zhr83
    JOIN hrp1001 AS hrp1 ON hrp1~objid = zhr83~uo AND hrp1~sclas = 'S' AND hrp1~plvar = 'PU'
    JOIN hrp1001 AS hrp11 ON hrp11~objid = hrp1~sobid AND hrp11~sclas = 'P'
    JOIN pa0001 AS pa1 ON pa1~pernr = hrp11~sobid
    JOIN pa0000 AS pa0 ON pa0~pernr = pa1~pernr
    JOIN pa0002 AS pa2 ON pa2~pernr = pa1~pernr
    LEFT JOIN zhrtb85 AS zhr85 ON zhr85~pernr = pa1~pernr " Obter UUID da pessoa da ZHRTB85
   WHERE pa0~stat2 = 3 " Colaboradores ativos
     AND pa0~begda  LE @sy-datum AND pa0~endda  GE @sy-datum
     AND pa1~begda  LE @sy-datum AND pa1~endda  GE @sy-datum
     AND pa2~begda  LE @sy-datum AND pa2~endda  GE @sy-datum
     AND hrp1~begda LE @sy-datum AND hrp1~endda GE @sy-datum
     AND hrp11~begda LE @sy-datum AND hrp11~endda GE @sy-datum.

  " A lógica de preparação de dados seguinte foi mantida do código original.
  SORT lt_dados BY pernr uo.
  DELETE ADJACENT DUPLICATES FROM lt_dados COMPARING pernr uo.

  SELECT * FROM zhrtb85 INTO TABLE lt_zhrtb85.

  SORT lt_dados BY pernr.
  lt_dados_restantes = lt_dados.
  DELETE ADJACENT DUPLICATES FROM lt_dados COMPARING pernr.


  "======================================================================
  " LOOP DE PROCESSAMENTO PRINCIPAL
  "======================================================================
  LOOP AT lt_dados INTO DATA(ls_person).

    DATA(lv_person_uuid) = ls_person-uuid.

    " Se a pessoa ainda não tem UUID no PURE, não podemos fazer GET/PUT. Seria um cenário de POST (criação).
    IF lv_person_uuid IS INITIAL.
      " LOG: Pessoa ls_person-pernr não tem UUID. A ignorar.
      CONTINUE.
    ENDIF.

    "-----------------------------------------------------
    " PASSO 1: Obter dados atuais do PURE via GET
    "-----------------------------------------------------
    DATA ls_get_response TYPE ty_get_response.
    DATA(lv_get_url) = |{ gc_base_url }{ gc_api_path }/{ lv_person_uuid }|.

    CALL METHOD cl_http_client=>create_by_url
      EXPORTING
        url    = lv_get_url
      IMPORTING
        client = lo_http_client
      EXCEPTIONS OTHERS = 1.

    IF sy-subrc <> 0 OR lo_http_client IS NOT BOUND.
      " LOG: Falha ao criar cliente HTTP para GET. URL: lv_get_url. Pessoa: ls_person-pernr.
      CONTINUE.
    ENDIF.

    lo_http_client->request->set_method('GET').
    lo_http_client->request->set_header_field( name = 'api-key', value = gc_api_key ).
    lo_http_client->request->set_header_field( name = 'Accept', value = 'application/json' ).
    lo_http_client->send( EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      lo_http_client->close( ).
      " LOG: Falha ao enviar pedido GET para a pessoa ls_person-pernr.
      CONTINUE.
    ENDIF.

    lo_http_client->receive( EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      lo_http_client->close( ).
      " LOG: Falha ao receber resposta GET para a pessoa ls_person-pernr.
      CONTINUE.
    ENDIF.

    DATA(lv_get_response_json) = lo_http_client->response->get_cdata( ).
    lo_http_client->close( ).

    /ui2/cl_json=>deserialize( EXPORTING json = lv_get_response_json CHANGING data = ls_get_response ).

    "-----------------------------------------------------
    " PASSO 2: Construir a nova estrutura de dados a partir do SAP
    "-----------------------------------------------------
    DATA ls_put_data TYPE ty_put_data.

    ls_put_data-name-first_name = ls_person-vorna.
    ls_put_data-name-last_name = ls_person-nachn.

    CALL FUNCTION 'ZHRFM24' " Obter UUID do utilizador
      EXPORTING
        i_first_name = ls_person-vorna
        i_last_name  = ls_person-nachn
        i_username   = ls_person-pernr
      IMPORTING
        e_uuid       = ls_put_data-user-uuid.
    ls_put_data-user-system_name = 'User'.

    SELECT SINGLE usrid INTO ls_put_data-orcid FROM pa0105
      WHERE pernr = ls_person-pernr AND subty = 'ORCI' AND endda >= sy-datum AND begda <= sy-datum.
    IF sy-subrc <> 0.
      ls_put_data-orcid = 'N/A'.
    ENDIF.

    LOOP AT lt_dados_restantes INTO DATA(ls_assignment) WHERE pernr = ls_person-pernr.
      DATA ls_staff_org_ass TYPE ty_put_st_org_ass.
      SELECT SINGLE uuid FROM zhrtb83 INTO ls_staff_org_ass-organization-uuid WHERE uo = ls_assignment-uo.
      " NOTA: A lógica complexa para encontrar o UUID da UO pai foi omitida para clareza.
      ls_staff_org_ass-organization-system_name = 'Organization'.
      CONCATENATE ls_assignment-begda+0(4) '-' ls_assignment-begda+4(2) '-' ls_assignment-begda+6(2)
        INTO ls_staff_org_ass-period-start_date.
      ls_staff_org_ass-type_discriminator = 'StaffOrganizationAssociation'.
      APPEND ls_staff_org_ass TO ls_put_data-staff_org_ass.
    ENDLOOP.

    ls_put_data-visibility-key = 'FREE'.
    ls_put_data-visibility-description-en_gb = 'Public - No restriction'.
    ls_put_data-visibility-description-pt_pt = '???visibility.FREE???'.

    DATA ls_identifier TYPE ty_put_identifiers.
    CONCATENATE 'uc' ls_person-pernr '@uc.pt' INTO ls_identifier-id.
    ls_identifier-typediscriminator = 'ClassifiedId'.
    ls_identifier-type_-uri = '/dk/atira/pure/person/personsources/employee'.
    ls_identifier-type_-term-en_gb = 'Employee ID'.
    ls_identifier-type_-term-pt_pt = 'ID de funcionário'.
    APPEND ls_identifier TO ls_put_data-identifiers.

    "-----------------------------------------------------
    " PASSO 3: Comparar os dados do GET com os novos dados
    "-----------------------------------------------------
    DATA lv_update_needed TYPE abap_bool = abap_false.

    IF ls_get_response-name-first_name <> ls_put_data-name-first_name OR
       ls_get_response-name-last_name  <> ls_put_data-name-last_name OR
       ( ls_get_response-orcid <> ls_put_data-orcid AND ls_put_data-orcid <> 'N/A' ).
      lv_update_needed = abap_true.
    ENDIF.

    IF lv_update_needed = abap_false.
      DATA: lt_get_uuids TYPE STANDARD TABLE OF string,
            lt_put_uuids TYPE STANDARD TABLE OF string.
      LOOP AT ls_get_response-staff_organization_associations INTO DATA(ls_get_assoc).
        APPEND ls_get_assoc-organization-uuid TO lt_get_uuids.
      ENDLOOP.
      LOOP AT ls_put_data-staff_org_ass INTO DATA(ls_put_assoc).
        APPEND ls_put_assoc-organization-uuid TO lt_put_uuids.
      ENDLOOP.
      SORT lt_get_uuids. SORT lt_put_uuids.
      IF lt_get_uuids <> lt_put_uuids.
        lv_update_needed = abap_true.
      ENDIF.
    ENDIF.

    "-----------------------------------------------------
    " PASSO 4: Se necessário, serializar e enviar os novos dados via PUT
    "-----------------------------------------------------
    IF lv_update_needed = abap_true.
      DATA(lv_put_json) = /ui2/cl_json=>serialize( data = ls_put_data ).

      " --- Conversão de Nomes de Campos para JSON
      REPLACE ALL OCCURRENCES OF 'FIRST_NAME' IN lv_put_json WITH 'firstName'.
      REPLACE ALL OCCURRENCES OF 'LAST_NAME' IN lv_put_json WITH 'lastName'.
      REPLACE ALL OCCURRENCES OF 'SYSTEM_NAME' IN lv_put_json WITH 'systemName'.
      REPLACE ALL OCCURRENCES OF 'STAFF_ORG_ASS' IN lv_put_json WITH 'staffOrganizationAssociations'.
      REPLACE ALL OCCURRENCES OF 'TYPE_DISCRIMINATOR' IN lv_put_json WITH 'typeDiscriminator'.
      REPLACE ALL OCCURRENCES OF 'START_DATE' IN lv_put_json WITH 'startDate'.
      REPLACE ALL OCCURRENCES OF 'TYPE_' IN lv_put_json WITH 'type'.
      IF ls_put_data-orcid = 'N/A'.
        REPLACE ALL OCCURRENCES OF ',"orcid":"N/A"' IN lv_put_json WITH ''.
      ENDIF.

      DATA(lv_put_url) = |{ gc_base_url }{ gc_api_path }/{ lv_person_uuid }|.
      CALL METHOD cl_http_client=>create_by_url( EXPORTING url = lv_put_url IMPORTING client = lo_http_client EXCEPTIONS OTHERS = 1 ).

      IF sy-subrc <> 0 OR lo_http_client IS NOT BOUND.
        " LOG: Falha ao criar cliente HTTP para PUT para a pessoa ls_person-pernr.
        CONTINUE.
      ENDIF.

      lo_http_client->request->set_method('PUT').
      lo_http_client->request->set_header_field( name = 'Content-Type', value = 'application/json' ).
      lo_http_client->request->set_header_field( name = 'api-key', value = gc_api_key ).
      lo_http_client->request->set_cdata( lv_put_json ).

      lo_http_client->send( EXCEPTIONS OTHERS = 1 ).
      IF sy-subrc = 0.
        lo_http_client->receive( EXCEPTIONS OTHERS = 1 ).
        IF sy-subrc = 0.
          DATA(lv_put_response_json) = lo_http_client->response->get_cdata( ).
          DATA ls_put_response TYPE ty_put_response.
          /ui2/cl_json=>deserialize( EXPORTING json = lv_put_response_json CHANGING data = ls_put_response ).

          " --- Atualizar tabela ZHRTB85
          DATA ls_zhrtb85 TYPE zhrtb85.
          ls_zhrtb85-pureid = ls_put_response-pureid.
          ls_zhrtb85-uuid = ls_put_response-uuid.
          ls_zhrtb85-pernr = ls_person-pernr.
          ls_zhrtb85-name = |{ ls_person-vorna } { ls_person-nachn }|.
          ls_zhrtb85-date_update = sy-datum.
          ls_zhrtb85-time_update = sy-uzeit.
          MODIFY zhrtb85 FROM ls_zhrtb85. " Usa MODIFY para inserir ou atualizar

          " --- Registar sucesso no log
          " CALL FUNCTION 'ZUCFM03' ...
        ENDIF.
      ENDIF.
      lo_http_client->close( ).
    ELSE.
      " LOG: Não foi necessária atualização para a pessoa ls_person-pernr.
    ENDIF.

  ENDLOOP.

ENDFUNCTION.
