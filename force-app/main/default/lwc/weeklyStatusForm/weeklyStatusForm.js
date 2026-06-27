import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import getProjects from '@salesforce/apex/weeklyStatusFormController.getProjects';
import saveFeedback from '@salesforce/apex/weeklyStatusFormController.saveFeedback';
import getLatestDraft from '@salesforce/apex/weeklyStatusFormController.getLatestDraft';
import getFeedbackFiles from '@salesforce/apex/weeklyStatusFormController.getFeedbackFiles';
import deleteFile from '@salesforce/apex/weeklyStatusFormController.deleteFile';

const EMPTY_FORM = Object.freeze({
    project: '',
    submitter: '',
    reportDate: '',
    reportingWeek: '',
    projectStatus: '',
    projectPhase: '',
    completion: 0,
    progressSummary: '',
    plannedActivities: '',
    nextWeekPlan: '',
    riskBlockers: '',
    notesForLeadership: '',
    teamMorale: ''
});

export default class WeeklyStatusForm extends LightningElement {

    @api recordId;
    @track formData = { ...EMPTY_FORM };
    statusError = false;
    isSubmitting = false;
    feedbackId;
    @track files = [];


    /* ───── Project dropdown options ───── */
    projectOptions = [];
    projectsLoaded = false;
    projectsError;
    projects = [];

    connectedCallback() {
        this.formData.reportDate =
            new Date().toISOString().split('T')[0];

        this.loadDraft();



    }

    @wire(getRecord, {
        recordId: USER_ID,
        fields: [NAME_FIELD]
    })
    wiredUser({ data }) {
        if (data) {
            this.formData.submitter = data.fields.Name.value;
        }
    }

    @wire(getProjects)
    wiredProjects({ error, data }) {
        if (data) {
            this.projects = data;
            this.projectOptions = data.map(proj => ({
                label: proj.Name,
                value: proj.Id
            }));
            this.projectsLoaded = true;
            this.projectsError = undefined;
        } else if (error) {
            this.projectsError = error.body ? error.body.message : 'Failed to load projects.';
            this.projectOptions = [];
            this.projectsLoaded = true;
        }
    }

    /* ───── Project Phase picklist options ───── */
    get phaseOptions() {
        return [
            { label: 'Initiation', value: 'Initiation' },
            { label: 'Planning', value: 'Planning' },
            { label: 'Execution', value: 'Execution' },
            { label: 'Monitoring', value: 'Monitoring' },
            { label: 'Closure', value: 'Closure' }
        ];
    }
    get emojiButtonsStatus() {

    }

    /* ───── Status pill options (computed) ───── */
    get statusOptions() {
        const selected = this.formData.projectStatus;
        return [
            {
                value: 'On Track',
                label: 'On Track',
                icon: 'utility:success',
                className:
                    'status-pill on-track' +
                    (selected === 'On Track' ? ' selected' : '')
            },
            {
                value: 'At Risk',
                label: 'At Risk',
                icon: 'utility:warning',
                className:
                    'status-pill at-risk' +
                    (selected === 'At Risk' ? ' selected' : '')
            },
            {
                value: 'Off Track',
                label: 'Off Track',
                icon: 'utility:error',
                className:
                    'status-pill off-track' +
                    (selected === 'Off Track' ? ' selected' : '')
            }
        ];
    }

    /* ───── Completion display ───── */
    get completionDisplay() {
        return `${this.formData.completion}%`;
    }

    /* ───── Handlers ───── */
    handleInputChange(event) {
        const field = event.target.dataset.field;
        this.formData = { ...this.formData, [field]: event.target.value };
    }

    async handleProjectChange(event) {

        const projectId = event.detail.value;
        console.log('project id is: ' + projectId)

        this.formData = {
            ...this.formData,
            project: projectId
        };

        const selectedProject =
            this.projects.find(p => p.Id === projectId);
        console.log('selected project is: ' + JSON.stringify(selectedProject))

        if (!selectedProject?.Start_Date__c) {

            this.formData = {
                ...this.formData,
                reportingWeek: ''
            };

            return;
        }

        const startDate = new Date(selectedProject.Start_Date__c);
        const today = new Date();

        const diffDays = Math.floor(
            (today - startDate) / (1000 * 60 * 60 * 24)
        );


        const projectWeek =
            Math.floor(diffDays / 7) + 1;

        console.log('project week: ' + projectWeek)
        this.formData = {
            ...this.formData,
            reportingWeek: `Week ${projectWeek}`
        };

    }

    handlePhaseChange(event) {
        this.formData = { ...this.formData, projectPhase: event.detail.value };
    }

    handleCompletionChange(event) {
        this.formData = { ...this.formData, completion: Number(event.target.value) };
    }

    handleStatusSelect(event) {
        const value = event.currentTarget.dataset.value;
        this.formData = { ...this.formData, projectStatus: value };
        this.statusError = false;
    }

    handleReset() {
        this.formData = { ...EMPTY_FORM };
        this.statusError = false;
        this.template
            .querySelectorAll('lightning-input, lightning-textarea, lightning-combobox, lightning-slider')
            .forEach((el) => {
                if (el.setCustomValidity) {
                    el.setCustomValidity('');
                    el.reportValidity();
                }
            });
        const emojiButtons = this.template.querySelectorAll('.emoji-btn');
        emojiButtons.forEach(button => {
            emojiButtons.forEach(btn => btn.classList?.remove('active'));
        });
        this.formData = { ...EMPTY_FORM };


    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async saveInitialDraft() {
        const feedback = {
            Id: this.feedbackId,
            Name: `${this.formData.submitter} - ${this.formData.reportingWeek}`,
            Project__c: this.formData.project,
            Reporting_Week__c: this.formData.reportingWeek,
            At_Risk__c: this.formData.projectStatus === 'At Risk',
            Blocked__c: this.formData.projectStatus === 'Off Track',
            Completion__c: this.formData.completion,
            Project_Phase__c: this.formData.projectPhase,
            Progress_Summary_or_Key_Accomplishments__c: this.formData.progressSummary,
            Next_Week_s_plan__c: this.formData.nextWeekPlan,
            Planned_Activities_Deliverables__c: this.formData.plannedActivities,
            Risk_Blockers__c: this.formData.riskBlockers,
            Notes_for_Leadership__c: this.formData.notesForLeadership,
            Team_Morale__c: this.formData.teamMorale,
            Status__c: 'Draft'
        };
        try {
            this.feedbackId = await saveFeedback({ feedback }).then(console.log('feedback id: ' + this.feedbackId));

        } catch (error) {
            const msg = error.body ? error.body.message : 'An unexpected error occurred.';
            this.showToast('Error', msg, 'error');
        }
    }
    async handleSaveDraft() {

        /* 3. Build the Feedback__c sObject */
        const feedback = {
            Id: this.feedbackId,
            Name: `${this.formData.submitter} - ${this.formData.reportingWeek}`,
            Project__c: this.formData.project,
            Reporting_Week__c: this.formData.reportingWeek,
            At_Risk__c: this.formData.projectStatus === 'At Risk',
            Blocked__c: this.formData.projectStatus === 'Off Track',
            Completion__c: this.formData.completion,
            Project_Phase__c: this.formData.projectPhase,
            Progress_Summary_or_Key_Accomplishments__c: this.formData.progressSummary,
            Next_Week_s_plan__c: this.formData.nextWeekPlan,
            Planned_Activities_Deliverables__c: this.formData.plannedActivities,
            Risk_Blockers__c: this.formData.riskBlockers,
            Notes_for_Leadership__c: this.formData.notesForLeadership,
            Team_Morale__c: this.formData.teamMorale,
            Status__c: 'Draft'
        };

        /* 4. Call Apex to insert */
        this.isSubmitting = true;
        try {
            const feedbackId = await saveFeedback({ feedback });
            this.showToast(
                'Success',
                `Weekly status report saved! (ID: ${feedbackId})`,
                'success'
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            const msg = error.body ? error.body.message : 'An unexpected error occurred.';
            this.showToast('Error', msg, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }
    async handleSubmit() {
        /* 1. Validate base inputs */
        const inputs = [
            ...this.template.querySelectorAll('lightning-input'),
            ...this.template.querySelectorAll('lightning-textarea'),
            ...this.template.querySelectorAll('lightning-combobox')
        ];
        const allValid = inputs.reduce((valid, cmp) => {
            cmp.reportValidity();
            return valid && cmp.checkValidity();
        }, true);

        /* 2. Validate status selection */
        if (!this.formData.projectStatus) {
            this.statusError = true;
        }

        if (!allValid || this.statusError) {
            this.showToast(
                'Validation Error',
                'Please complete all required fields and select a project status.',
                'error'
            );
            return;
        }

        /* 3. Build the Feedback__c sObject */
        const feedback = {
            Id: this.feedbackId,
            Name: `${this.formData.submitter} - ${this.formData.reportingWeek}`,
            Project__c: this.formData.project,
            Reporting_Week__c: this.formData.reportingWeek,
            At_Risk__c: this.formData.projectStatus === 'At Risk',
            Blocked__c: this.formData.projectStatus === 'Off Track',
            Completion__c: this.formData.completion,
            Project_Phase__c: this.formData.projectPhase,
            Progress_Summary_or_Key_Accomplishments__c: this.formData.progressSummary,
            Next_Week_s_plan__c: this.formData.nextWeekPlan,
            Planned_Activities_Deliverables__c: this.formData.plannedActivities,
            Risk_Blockers__c: this.formData.riskBlockers,
            Notes_for_Leadership__c: this.formData.notesForLeadership,
            Team_Morale__c: this.formData.teamMorale,
            Status__c: 'Submitted'
        };

        /* 4. Call Apex to insert */
        this.isSubmitting = true;
        try {
            const feedbackId = await saveFeedback({ feedback });
            this.showToast(
                'Success',
                `Weekly status report saved! (ID: ${feedbackId})`,
                'success'
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            const msg = error.body ? error.body.message : 'An unexpected error occurred.';
            this.showToast('Error', msg, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    handleEmojiClick(event) {
        const emojiButtons = this.template.querySelectorAll('.emoji-btn');
        emojiButtons.forEach(button => {
            emojiButtons.forEach(btn => btn.classList?.remove('active'));
        });
        event.currentTarget?.classList?.add('active');
        this.formData = { ...this.formData, teamMorale: event.currentTarget?.dataset?.id }
    }
    /* ───── Utility ───── */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
    async createDraftFeedback() {

        const feedback = {

            Name: `${this.formData.submitter} - DRAFT`,
            Project__c: this.formData.project || null,
            Reporting_Week__c: this.formData.reportingWeek || '',
            At_Risk__c: this.formData.projectStatus === 'At Risk',
            Blocked__c: this.formData.projectStatus === 'Off Track',
            Completion__c: this.formData.completion || 0
        };

        const id = await saveFeedback({ feedback });

        this.feedbackId = id;
        return id;
    }
    async loadDraft() {

        const draft = await getLatestDraft();

        if (!draft?.Id) {
            await this.saveInitialDraft();
            return;
        };

        this.feedbackId = draft.Id;


        this.formData = {
            ...this.formData,
            project: draft.Project__c,
            projectStatus: draft.At_Risk__c
                ? 'At Risk'
                : draft.Blocked__c
                    ? 'Off Track'
                    : 'On Track',
            projectPhase: draft.Project_Phase__c,
            completion: draft.Completion__c,
            progressSummary: draft.Progress_Summary_or_Key_Accomplishments__c,
            plannedActivities: draft.Planned_Activities_Deliverables__c,
            nextWeekPlan: draft.Next_Week_s_plan__c,
            riskBlockers: draft.Risk_Blockers__c,
            notesForLeadership: draft.Notes_for_Leadership__c,
            teamMorale: draft.Team_Morale__c,
            reportingWeek: draft.Reporting_Week__c
        };
        await this.loadFiles();
        console.log('formdata draft loaded: ' + JSON.stringify(this.formData))
        this.applyEmojiFromDraft()
    }
    applyEmojiFromDraft() {

        const value = this.formData.teamMorale;

        if (!value) return;

        this.template.querySelectorAll('.emoji-btn')
            .forEach(btn => {

                if (btn.dataset.id === value) {
                    btn.classList.add('active');
                } else {
                    btn.classList.remove('active');
                }

            });
    }
    async loadFiles() {
        console.log('feedback id: ' + this.feedbackId);

        if (!this.feedbackId) return;

        const data = await getFeedbackFiles({
            recordId: this.feedbackId
        });

        const mappedFiles = data.map(file => {
            const title = file.ContentDocument.Title;
            const versionId = file.ContentDocument.LatestPublishedVersionId;

            const isImg = /\.(jpg|jpeg|png|gif|webp)$/i.test(title);
            console.log('is image: ' + isImg);
            return {
                id: file.ContentDocumentId,
                title: title,
                versionId: versionId,
                url: `/sfc/servlet.shepherd/version/download/${versionId}`,
                isImage: isImg,
                thumbnailUrl: `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB120BY90&versionId=${versionId}`
            };
        });

        console.log('mapped files: ' + JSON.stringify(mappedFiles));
        this.files = [...mappedFiles];
    }

    async handleUploadFinished() {

        await this.loadFiles();
    }

    async handleDeleteFile(event) {

        const contentDocumentId =
            event.currentTarget.dataset.id;

        try {

            await deleteFile({
                contentDocumentId,
                feedbackId: this.feedbackId
            });

            await this.loadFiles();

            this.showToast(
                'Success',
                'File deleted.',
                'success'
            );

        } catch (error) {

            this.showToast(
                'Error',
                error.body?.message || 'Failed to delete file.',
                'error'
            );
        }
    }
    get emojiValue() {
        return this.formData.teamMorale;
    }


}