import { LightningElement, api, wire, track } from 'lwc';
import getLessonsForStudent from '@salesforce/apex/StudentLessonService.getLessonsForStudent';
import getBadgesForStudent from '@salesforce/apex/StudentLessonService.getBadgesForStudent';
import setStepCompleted from '@salesforce/apex/StudentLessonService.setStepCompleted';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class StudentLessonsViewer extends LightningElement {
  @api recordId;
  @track lessons = [];
  @track error;
  @track badges = [];
  

  // LESSONS
  @wire(getLessonsForStudent, { studentId: '$recordId' })
  wiredLessons({ data, error }) {
    console.log('[Lessons] wire fired. recordId =', this.recordId);

    if (data) {
      try {
        console.log('[Lessons] raw length:', Array.isArray(data) ? data.length : '(not array)');
        this.lessons = (data || []).map((lesson, idx) => {
          if (!lesson?.id) console.warn(`[Lessons] item ${idx} missing id`, lesson);

          const steps = (lesson.steps || []).map((s, i) => ({
            ...s,
            saving: false,
            buttonLabel: s.completed ? 'Completed' : 'Complete step',
            buttonVariant: s.completed ? 'neutral' : 'brand-outline',
            buttonIconName: s.completed ? 'utility:check' : 'utility:success'
          }));

          return {
            ...lesson,
            steps,
            showSteps: false,
            stepButtonLabel: 'Show Steps',
            iconName: 'utility:chevronright'
          };
        });

        console.log('[Lessons] mapped summary:', this.lessons.map(l => ({
          id: l.id,
          name: l.lessonName,
          date: l.lessonDate,
          steps: Array.isArray(l.steps) ? l.steps.length : 0,
          prog: `${l.completedSteps}/${l.totalSteps}`,
          completed: l.completed
        })));
      } catch (e) {
        console.error('[Lessons] mapping exception:', e);
        this.lessons = [];
        this.error = e;
      }
    } else if (error) {
      console.error('[Lessons] error:', error);
      this.error = error;
      this.lessons = [];
    }
  }

  // BADGES
  @wire(getBadgesForStudent, { studentId: '$recordId' })
  wiredBadges({ data, error }) {
    console.log('[Badges] wire fired. recordId =', this.recordId);
    if (data) {
      try {
        console.log('[Badges] raw length:', Array.isArray(data) ? data.length : '(not array)');
        this.badges = (data || []).map((b, idx) => ({
          id: b.Id,
          name: b.Name,
          iconName: b.Icon_Name__c || 'utility:award',
          type: b.Badge_Type__c,
          lessonName: b.Lesson__r?.Name,
          date: b.Award_Date__c
        }));
        console.log('[Badges] mapped:', this.badges);
      } catch (e) {
        console.error('[Badges] mapping exception:', e);
        this.badges = [];
        this.error = e;
      }
    } else if (error) {
      console.error('[Badges] error:', error);
      this.error = error;
      this.badges = [];
    }
  }

  // Toggle lesson steps open/closed + chevron icon
  toggleSteps(event) {
    const clickedId = event?.currentTarget?.dataset?.id;
    console.log('[Toggle] clicked data-id =', clickedId);
    if (!clickedId) return;

    this.lessons = (this.lessons || []).map(lesson => {
      const isMatch = String(lesson.id) === String(clickedId);
      if (isMatch) {
        const show = !lesson.showSteps;
        return {
          ...lesson,
          showSteps: show,
          stepButtonLabel: show ? 'Hide Steps' : 'Show Steps',
          iconName: show ? 'utility:chevrondown' : 'utility:chevronright'
        };
      }
      return lesson;
    });
  }

  // Complete or reopen a single step (optimistic update + reconcile with server counts)
  async handleCompleteStep(event) {
    const lessonId = event.currentTarget.dataset.lessonId;
    const stepId = event.currentTarget.dataset.stepId;
    console.log('[CompleteStep] lessonId:', lessonId, 'stepId:', stepId);

    const lessonIdx = this.lessons.findIndex(l => String(l.id) === String(lessonId));
    if (lessonIdx < 0) return;
    const stepIdx = this.lessons[lessonIdx].steps.findIndex(s => String(s.id) === String(stepId));
    if (stepIdx < 0) return;

    const step = this.lessons[lessonIdx].steps[stepIdx];
    const newCompleted = !step.completed;

    // Optimistic UI
    this.lessons = this.lessons.map((l, li) => {
      if (li !== lessonIdx) return l;
      const steps = l.steps.map((s, si) => {
        if (si !== stepIdx) return s;
        return {
          ...s,
          saving: true,
          completed: newCompleted,
          buttonLabel: newCompleted ? 'Completed' : 'Complete step',
          buttonVariant: newCompleted ? 'neutral' : 'brand-outline',
          buttonIconName: newCompleted ? 'utility:check' : 'utility:success'
        };
      });
      // Also update lesson-level counts locally for snappy UI
      const completedSteps = (l.completedSteps || 0) + (newCompleted ? 1 : -1);
      const totalSteps = l.totalSteps || steps.length;
      return {
        ...l,
        steps,
        completedSteps,
        totalSteps,
        completed: totalSteps > 0 && completedSteps === totalSteps
      };
    });

    try {
      const result = await setStepCompleted({
        studentLessonId: lessonId,
        lessonStepId: stepId,
        completed: newCompleted
      });
      console.log('[CompleteStep] server result:', result);

      // Reconcile with server truth
      this.lessons = this.lessons.map((l, li) => {
        if (li !== lessonIdx) return l;
        const steps = l.steps.map((s, si) => {
          if (si !== stepIdx) return s;
          return {
            ...s,
            saving: false,
            completed: result?.completed ?? newCompleted,
            completedDate: result?.completedDate ?? s.completedDate,
            buttonLabel: (result?.completed ?? newCompleted) ? 'Completed' : 'Complete step',
            buttonVariant: (result?.completed ?? newCompleted) ? 'neutral' : 'brand-outline',
            buttonIconName: (result?.completed ?? newCompleted) ? 'utility:check' : 'utility:success'
          };
        });
        return {
          ...l,
          steps,
          completedSteps: result?.completedSteps ?? l.completedSteps,
          totalSteps: result?.totalSteps ?? l.totalSteps,
          completed: result?.lessonCompleted ?? l.completed
        };
      });

      this.dispatchEvent(new ShowToastEvent({
        title: newCompleted ? 'Step completed' : 'Step reopened',
        message: this.lessons[lessonIdx].lessonName,
        variant: 'success'
      }));
    } catch (e) {
      console.error('[CompleteStep] error:', e);

      // Revert optimistic change
      this.lessons = this.lessons.map((l, li) => {
        if (li !== lessonIdx) return l;
        const steps = l.steps.map((s, si) => {
          if (si !== stepIdx) return s;
          const revert = !newCompleted;
          return {
            ...s,
            saving: false,
            completed: revert,
            buttonLabel: revert ? 'Completed' : 'Complete step',
            buttonVariant: revert ? 'neutral' : 'brand-outline',
            buttonIconName: revert ? 'utility:check' : 'utility:success'
          };
        });
        // Fix counts back
        const completedSteps = (l.completedSteps || 0) + (newCompleted ? -1 : 1);
        return {
          ...l,
          steps,
          completedSteps,
          completed: l.totalSteps > 0 && completedSteps === l.totalSteps
        };
      });

      this.dispatchEvent(new ShowToastEvent({
        title: 'Update failed',
        message: e?.body?.message || 'Could not update step',
        variant: 'error'
      }));
    }
  }
}
